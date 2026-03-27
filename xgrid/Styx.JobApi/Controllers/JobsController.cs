using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Mvc;
using Styx.JobApi.Models;
using Styx.JobApi.Repositories;
using Styx.JobApi.Services;

namespace Styx.JobApi.Controllers;

[ApiController]
public class JobsController : ControllerBase
{
    private readonly ModelJobRepository _modelJobRepo;
    private readonly DataJobRepository _dataJobRepo;
    private readonly SchedulerRepository _schedulerRepo;
    private readonly JobDispatchService _dispatchService;
    private readonly string _shareBasePath;
    private readonly int _heartbeatTimeoutSeconds;

    public JobsController(
        ModelJobRepository modelJobRepo,
        DataJobRepository dataJobRepo,
        SchedulerRepository schedulerRepo,
        JobDispatchService dispatchService,
        IConfiguration config)
    {
        _modelJobRepo = modelJobRepo;
        _dataJobRepo = dataJobRepo;
        _schedulerRepo = schedulerRepo;
        _dispatchService = dispatchService;
        _shareBasePath = config["Orchestrator:ShareBasePath"]!;
        _heartbeatTimeoutSeconds = config.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds");
    }

    [HttpPost("jobs")]
    public async Task<IActionResult> PostJob([FromBody] JobRequest request)
    {
        var modelJob = await _modelJobRepo.GetByIdAsync(request.ModelJobId);
        if (modelJob is null)
            return NotFound(new { error = $"ModelJob {request.ModelJobId} not found" });
        if (modelJob.IsPurged)
            return BadRequest(new { error = "ModelJob is purged" });
        if (modelJob.SchedulerId.HasValue)
            return Conflict(new { error = "ModelJob is already running" });

        // Build parent_ids from data_job_parent
        var dataJobs = (await _dataJobRepo.GetByModelJobIdAsync(request.ModelJobId)).ToList();
        var parentLinks = (await _dataJobRepo.GetParentIdsAsync(request.ModelJobId)).ToList();

        var parentMap = dataJobs.ToDictionary(dj => dj.Id, _ => new List<long>());
        foreach (var (jobId, parentJobId) in parentLinks)
            if (parentMap.ContainsKey(jobId))
                parentMap[jobId].Add(parentJobId);

        // Create share directory and write jobs.json
        var folderName = $"{request.ModelJobId}_{DateTime.UtcNow:yyyyMMddTHHmmss}";
        var folderPath = Path.Combine(_shareBasePath, folderName);
        Directory.CreateDirectory(folderPath);
        var jobsFilePath = Path.Combine(folderPath, "jobs.json");

        var jobsFile = new
        {
            model_job_id = request.ModelJobId,
            data_jobs = dataJobs.Select(dj => new
            {
                id = dj.Id,
                parent_ids = parentMap[dj.Id]
            })
        };

        await System.IO.File.WriteAllTextAsync(jobsFilePath,
            JsonSerializer.Serialize(jobsFile, new JsonSerializerOptions { WriteIndented = false }));

        // Persist job_path so the watchdog can re-dispatch if needed
        using var conn = new Npgsql.NpgsqlConnection(HttpContext.RequestServices
            .GetRequiredService<IConfiguration>().GetConnectionString("Postgres"));
        await conn.OpenAsync();
        using var tx = await conn.BeginTransactionAsync();
        await _modelJobRepo.SetJobPathAsync(conn, tx, request.ModelJobId, jobsFilePath);
        await tx.CommitAsync();

        var status = await _dispatchService.TryDispatchAsync(request.ModelJobId, jobsFilePath);

        return Accepted(new { model_job_id = request.ModelJobId, status });
    }

    [HttpGet("jobs/{modelJobId:long}")]
    public async Task<IActionResult> GetJob(long modelJobId)
    {
        var modelJob = await _modelJobRepo.GetByIdAsync(modelJobId);
        if (modelJob is null)
            return NotFound();

        var dataJobs = await _dataJobRepo.GetByModelJobIdAsync(modelJobId);
        return Ok(new { model_job = modelJob, data_jobs = dataJobs });
    }

    [HttpGet("schedulers/ping")]
    public async Task<IActionResult> PingSchedulers()
    {
        var schedulers = await _schedulerRepo.GetAllActiveAsync();
        var now = DateTime.UtcNow;
        var result = schedulers.Select(s => new
        {
            s.Id,
            s.Pid,
            s.Host,
            s.ModelJobId,
            s.Heartbeat,
            alive = (now - s.Heartbeat).TotalSeconds <= _heartbeatTimeoutSeconds
                ? "alive" : "stale"
        });
        return Ok(result);
    }
}
