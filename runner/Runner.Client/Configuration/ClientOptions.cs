namespace Runner.Client.Configuration;

public class ClientOptions
{
    public const string Section = "Runner";

    public string ConnectionString { get; set; } = string.Empty;

    /// <summary>Identifiant unique de ce runner (généré si vide)</summary>
    public string ServerId { get; set; } = string.Empty;

    /// <summary>Nom lisible affiché dans le dashboard</summary>
    public string FriendlyName { get; set; } = "Runner";

    /// <summary>Nombre de workers parallèles</summary>
    public int MaxConcurrentRunners { get; set; } = 4;

    /// <summary>Délai entre deux polls quand la file est vide (ms)</summary>
    public int PollingIntervalMs { get; set; } = 2000;

    /// <summary>Timeout max d'exécution d'une tâche (secondes, 0 = infini)</summary>
    public int TaskTimeoutSeconds { get; set; } = 300;

    /// <summary>Intervalle heartbeat (secondes)</summary>
    public int HeartbeatIntervalSeconds { get; set; } = 30;
}
