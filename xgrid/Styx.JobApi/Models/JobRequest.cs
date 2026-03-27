using System.Text.Json.Serialization;

namespace Styx.JobApi.Models;

public class JobRequest
{
    [JsonPropertyName("model_job_id")]
    public long ModelJobId { get; set; }
}
