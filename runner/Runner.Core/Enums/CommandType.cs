namespace Runner.Core.Enums;

public enum CommandType
{
    /// <summary>Commande shell : Process.Start(exe_name, args)</summary>
    Shell,

    /// <summary>Handler .NET : résolution via ITaskHandler.Name == exe_name</summary>
    DotNet
}
