namespace HpcLite.Domain.Models;

public static class RunStates
{
    public static string Created            = "Created";
    public static string Configuring        = "Configuring";
    public static string Submitted          = "Submitted";
    public static string Validating         = "Validating";
    public static string Queued             = "Queued";
    public static string Running            = "Running";
    public static string Finishing          = "Finishing";
    public static string Finished           = "Finished";
    public static string Failed             = "Failed";
    public static string Canceling          = "Canceling";
    public static string Canceled           = "Canceled";
    public static string ExternalValidation = "ExternalValidation";
}
