using System.Text.Json.Serialization;

namespace Styx.SchedulerProcess.Models;

public class JobsFile
{
    [JsonPropertyName("model_job_id")]
    public long ModelJobId { get; set; }

    [JsonPropertyName("data_jobs")]
    public List<JobsFileEntry> DataJobs { get; set; } = [];
}

public class JobsFileEntry
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("parent_ids")]
    public List<long> ParentIds { get; set; } = [];
}
