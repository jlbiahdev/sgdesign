using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Styx.Domain.Models;
using Styx.SchedulerProcess.Models;

namespace Styx.SchedulerProcess.Services;

public class SubJobExecutor
{
    private readonly HttpClient _httpClient;

    public SubJobExecutor(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    /// <summary>
    /// Returns true on HTTP 2xx, false otherwise (failure is logged, not thrown).
    /// The caller is responsible for updating DB state.
    /// </summary>
    public async Task<(bool Success, string? ErrorDetail)> ExecuteAsync(DataJobNode node, CancellationToken ct = default)
    {
        try
        {
            var response = await _httpClient.PostAsJsonAsync(
                $"datajobs/{node.Id}/execute",
                new { id = node.Id },
                ct);

            if (response.IsSuccessStatusCode)
                return (true, null);

            var body = await response.Content.ReadAsStringAsync(ct);
            return (false, $"HTTP {(int)response.StatusCode}: {body}");
        }
        catch (TaskCanceledException) when (!ct.IsCancellationRequested)
        {
            return (false, $"HTTP timeout after {_httpClient.Timeout.TotalSeconds}s");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }
}
