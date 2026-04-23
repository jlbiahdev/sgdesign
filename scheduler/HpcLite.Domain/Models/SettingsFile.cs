using System.Text.Json.Serialization;

namespace HpcLite.Domain.Models;

public class SettingsFile
{
    [JsonPropertyName("model_job_id")]
    public long ModelJobId { get; set; }

    [JsonPropertyName("data_jobs")]
    public List<DataJobEntry> DataJobs { get; set; } = [];
}

public class DataJobEntry
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("parent_ids")]
    public List<long> ParentIds { get; set; } = [];
}
