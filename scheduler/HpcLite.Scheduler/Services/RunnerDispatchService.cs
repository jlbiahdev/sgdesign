using Dapper;
using HpcLite.Scheduler.Repositories;
using Npgsql;
using System.Text;
using System.Text.Json;

namespace HpcLite.Scheduler.Services;

public class RunnerDispatchService
{
    private readonly string _connectionString;
    private readonly IHttpClientFactory _httpFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<RunnerDispatchService> _logger;

    // Prevents concurrent dispatch loops from racing each other.
    // A dispatch already in progress drains all pending jobs anyway.
    private readonly SemaphoreSlim _gate = new(1, 1);

    public RunnerDispatchService(
        IConfiguration configuration,
        IHttpClientFactory httpFactory,
        ILogger<RunnerDispatchService> logger)
    {
        _connectionString = configuration.GetConnectionString("Postgres")!;
        _httpFactory      = httpFactory;
        _configuration    = configuration;
        _logger           = logger;
    }

    /// Called by JobListenerService (on NOTIFY or poll fallback) and WatchdogService (after runner release).
    /// Loops until no pending job or no idle runner remains.
    public async Task TryDispatchAllPendingAsync()
    {
        if (!await _gate.WaitAsync(0))
            return; // another call is already draining the queue

        try
        {
            while (true)
            {
                var candidate = await TryClaimOneAsync();
                if (candidate is null) break;

                await CallAgentAsync(candidate);
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private NpgsqlConnection OpenConnection() => new(_connectionString);

    /// Claims one (model_job, runner) pair atomically in a single transaction.
    /// Both rows are locked with FOR UPDATE SKIP LOCKED, so concurrent Scheduler
    /// instances can never dispatch the same job or the same runner twice.
    private async Task<DispatchCandidate?> TryClaimOneAsync()
    {
        await using var conn = OpenConnection();
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();

        // Step 1 — find the oldest dispatchable Grid job (runner_id IS NULL, at least one type-1
        //          data_job Queued with all its parents Finished or no parents)
        var job = await conn.QuerySingleOrDefaultAsync<PendingJobRecord>(
            @"SELECT id, template_folder
              FROM model_job
              WHERE runner_id IS NULL
                AND template_folder IS NOT NULL
                AND EXISTS (
                    SELECT 1 FROM data_job dj
                    WHERE dj.parent_model_id = model_job.id
                      AND dj.state = 'Queued'
                      AND dj.job_command_type = 1
                      AND NOT EXISTS (
                          SELECT 1 FROM data_job_parent djp
                          JOIN data_job p ON p.id = djp.parent_job_id
                          WHERE djp.job_id = dj.id
                            AND p.state != 'Finished'
                      )
                )
              ORDER BY id ASC
              LIMIT 1
              FOR UPDATE SKIP LOCKED",
            transaction: tx);

        if (job is null)
        {
            await tx.RollbackAsync();
            return null;
        }

        // Step 2 — find an idle runner
        var runner = await conn.QuerySingleOrDefaultAsync<RunnerRecord>(
            @"SELECT id, name, host, exe_path
              FROM scheduler.runners
              WHERE status = 'idle'
              ORDER BY id ASC
              LIMIT 1
              FOR UPDATE SKIP LOCKED",
            transaction: tx);

        if (runner is null)
        {
            await tx.RollbackAsync();
            _logger.LogDebug("model_job {Id} pending — no idle runner available", job.Id);
            return null;
        }

        // Step 3 — claim both atomically
        await conn.ExecuteAsync(
            "UPDATE scheduler.runners   SET status='active', model_job_id=@jobId, started_at=NOW() WHERE id=@id",
            new { jobId = job.Id, id = runner.Id }, tx);

        await conn.ExecuteAsync(
            "UPDATE model_job SET runner_id=@runnerId WHERE id=@id",
            new { runnerId = runner.Id, id = job.Id }, tx);

        await tx.CommitAsync();

        _logger.LogInformation(
            "Claimed model_job {JobId} → runner '{Runner}' ({Host})",
            job.Id, runner.Name, runner.Host);

        return new DispatchCandidate(job, runner);
    }

    private async Task CallAgentAsync(DispatchCandidate c)
    {
        var agentPort = _configuration.GetValue<int>("Orchestrator:AgentPort", 5200);
        var agentUrl  = $"http://{c.Runner.Host}:{agentPort}/run";

        var body = JsonSerializer.Serialize(new
        {
            runner_id     = c.Runner.Id,
            exe_path      = c.Runner.ExePath,
            settings_path = c.Job.SettingsPath
        });

        try
        {
            var client   = _httpFactory.CreateClient();
            var response = await client.PostAsync(
                agentUrl,
                new StringContent(body, Encoding.UTF8, "application/json"));

            response.EnsureSuccessStatusCode();
            _logger.LogInformation(
                "Dispatched runner '{Runner}' to {Url} for model_job {JobId}",
                c.Runner.Name, agentUrl, c.Job.Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Agent unreachable for runner '{Runner}' at {Url} — rolling back model_job {JobId}",
                c.Runner.Name, agentUrl, c.Job.Id);

            // Rollback: release runner and clear model_job.runner_id
            await using var conn = OpenConnection();
            await conn.ExecuteAsync(
                "UPDATE scheduler.runners   SET status='idle', model_job_id=NULL, pid=NULL WHERE id=@id",
                new { id = c.Runner.Id });
            await conn.ExecuteAsync(
                "UPDATE model_job SET runner_id=NULL WHERE id=@id",
                new { id = c.Job.Id });
        }
    }

    private sealed record DispatchCandidate(PendingJobRecord Job, RunnerRecord Runner);
}
