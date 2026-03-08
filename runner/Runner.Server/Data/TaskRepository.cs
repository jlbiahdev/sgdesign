using Dapper;
using Npgsql;
using Runner.Core.Enums;
using Runner.Core.Interfaces;
using Runner.Core.Models;
using Runner.Server.Configuration;

namespace Runner.Server.Data;

public class TaskRepository : ITaskRepository
{
    private readonly string _connectionString;

    public TaskRepository(TaskFlowOptions options)
    {
        _connectionString = options.ConnectionString;
    }

    private NpgsqlConnection CreateConnection() => new(_connectionString);

    // ------------------------------------------------------------------
    // INSERT
    // ------------------------------------------------------------------

    public async Task<long> InsertAsync(TaskRecord task, CancellationToken ct = default)
    {
        const string sql = """
            INSERT INTO taskflow.task (external_id, state, command_type, exe_name, args)
            VALUES (@ExternalId, @State, @CommandType, @ExeName, @Args)
            RETURNING id;
            """;

        await using var conn = CreateConnection();
        await conn.OpenAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);

        var id = await conn.ExecuteScalarAsync<long>(sql, task, tx);

        // Historique initial
        await conn.ExecuteAsync("""
            INSERT INTO taskflow.task_state (task_id, name)
            VALUES (@TaskId, @Name)
            """,
            new { TaskId = id, Name = WorkStatus.Submitted.ToString() }, tx);

        // Compteur de tentatives
        await conn.ExecuteAsync("""
            INSERT INTO taskflow.attempt_counter (task_id, count)
            VALUES (@TaskId, 0)
            """,
            new { TaskId = id }, tx);

        await tx.CommitAsync(ct);
        return id;
    }

    // ------------------------------------------------------------------
    // READ
    // ------------------------------------------------------------------

    public async Task<TaskRecord?> GetByIdAsync(long id, CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        return await conn.QuerySingleOrDefaultAsync<TaskRecord>(
            "SELECT * FROM taskflow.task WHERE id = @id",
            new { id });
    }

    public async Task<IEnumerable<TaskRecord>> GetAllAsync(CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        return await conn.QueryAsync<TaskRecord>(
            "SELECT * FROM taskflow.task ORDER BY created_at DESC");
    }

    public async Task<IEnumerable<TaskStateRecord>> GetHistoryAsync(long id, CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        return await conn.QueryAsync<TaskStateRecord>(
            "SELECT * FROM taskflow.task_state WHERE task_id = @id ORDER BY created_at",
            new { id });
    }

    public async Task<IEnumerable<ServerRecord>> GetServersAsync(CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        return await conn.QueryAsync<ServerRecord>(
            "SELECT * FROM taskflow.server WHERE last_heartbeat_at > NOW() - INTERVAL '2 minutes' ORDER BY friendly_name");
    }

    // ------------------------------------------------------------------
    // ACQUIRE (SELECT FOR UPDATE SKIP LOCKED)
    // ------------------------------------------------------------------

    public async Task<TaskRecord?> TryAcquireNextAsync(string serverId, CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        await conn.OpenAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);

        var task = await conn.QuerySingleOrDefaultAsync<TaskRecord>("""
            SELECT * FROM taskflow.task
            WHERE state = 'Submitted'
            ORDER BY created_at
            FOR UPDATE SKIP LOCKED
            LIMIT 1
            """, transaction: tx);

        if (task is null)
        {
            await tx.RollbackAsync(ct);
            return null;
        }

        await conn.ExecuteAsync("""
            UPDATE taskflow.task SET state = 'Running' WHERE id = @id
            """, new { task.Id }, tx);

        await conn.ExecuteAsync("""
            INSERT INTO taskflow.task_state (task_id, name, server_id)
            VALUES (@TaskId, 'Running', @ServerId)
            """, new { TaskId = task.Id, ServerId = serverId }, tx);

        await conn.ExecuteAsync("""
            INSERT INTO taskflow.attempt_counter (task_id, count)
            VALUES (@TaskId, 1)
            ON CONFLICT (task_id) DO UPDATE SET count = attempt_counter.count + 1
            """, new { TaskId = task.Id }, tx);

        await tx.CommitAsync(ct);

        task.State = WorkStatus.Running.ToString();
        return task;
    }

    // ------------------------------------------------------------------
    // UPDATE STATE
    // ------------------------------------------------------------------

    public async Task UpdateStateAsync(long id, WorkStatus status, string serverId, string? reason = null, CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        await conn.OpenAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);

        await conn.ExecuteAsync("""
            UPDATE taskflow.task SET state = @State WHERE id = @Id
            """, new { State = status.ToString(), Id = id }, tx);

        await conn.ExecuteAsync("""
            INSERT INTO taskflow.task_state (task_id, name, server_id, reason)
            VALUES (@TaskId, @Name, @ServerId, @Reason)
            """, new { TaskId = id, Name = status.ToString(), ServerId = serverId, Reason = reason }, tx);

        await tx.CommitAsync(ct);
    }

    // ------------------------------------------------------------------
    // SERVER / HEARTBEAT
    // ------------------------------------------------------------------

    public async Task UpsertServerAsync(ServerRecord server, CancellationToken ct = default)
    {
        await using var conn = CreateConnection();
        await conn.OpenAsync(ct);
        await conn.ExecuteAsync("""
            INSERT INTO taskflow.server (id, friendly_name, last_heartbeat_at)
            VALUES (@Id, @FriendlyName, @LastHeartbeatAt)
            ON CONFLICT (id) DO UPDATE SET
                friendly_name     = EXCLUDED.friendly_name,
                last_heartbeat_at = EXCLUDED.last_heartbeat_at
            """, server);
    }
}
