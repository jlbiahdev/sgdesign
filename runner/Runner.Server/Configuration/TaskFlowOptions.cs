namespace Runner.Server.Configuration;

public class TaskFlowOptions
{
    public const string Section = "TaskFlow";

    public string ConnectionString { get; set; } = string.Empty;

    /// <summary>Active l'exposition des endpoints HTTP /taskflow/...</summary>
    public bool ExposeEndpoints { get; set; } = true;

    /// <summary>Préfixe des routes HTTP (ex: "/taskflow")</summary>
    public string RoutePrefix { get; set; } = "/taskflow";
}
