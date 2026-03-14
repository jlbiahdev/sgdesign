using Microsoft.AspNetCore.Mvc;
using Styx.Models.Enums;
using Styx.Models.Requests;
using Styx.Models.Responses;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class JobGridController : ControllerBase
{
    private static readonly DateTime _now = DateTime.UtcNow;

    /// <summary>Returns all jobs for the monitoring grid.</summary>
    [HttpGet("jobs")]
    [ProducesResponseType(typeof(JobListResponse), StatusCodes.Status200OK)]
    public IActionResult GetJobs()
    {
        var response = new JobListResponse
        {
            Status = "ok",
            Jobs =
            [
                new JobItem
                {
                    Id            = 1042,
                    Name          = "Savings_2022Y_central_run03",
                    UserAccountId = "jdupont",
                    UserName      = "jdupont",
                    Progress      = 100,
                    State         = JobState.Finished,
                    Priority      = JobPriority.Normal,
                    HasChildrens  = true,
                    GridCost      = 200,
                    Environment   = @"\\srvrbxassufp01\hpc\Cas01\4-Omen",
                    CreateTime    = _now.AddHours(-5),
                    SubmitTime    = _now.AddHours(-5).AddMinutes(1),
                    ChangeTime    = _now.AddHours(-2)
                },
                new JobItem
                {
                    Id            = 1043,
                    Name          = "NonLife_2023Y_run01",
                    UserAccountId = "mmartin",
                    UserName      = "mmartin",
                    Progress      = 72,
                    State         = JobState.Running,
                    Priority      = JobPriority.High,
                    HasChildrens  = true,
                    GridCost      = 80,
                    Environment   = @"\\srvrbxassufp01\hpc\Cas03\4-Omen",
                    CreateTime    = _now.AddHours(-1),
                    SubmitTime    = _now.AddHours(-1).AddMinutes(2),
                    ChangeTime    = _now.AddMinutes(-5)
                },
                new JobItem
                {
                    Id            = 1044,
                    Name          = "RiskLife_KP_2023Y",
                    UserAccountId = "jdupont",
                    UserName      = "jdupont",
                    Progress      = 0,
                    State         = JobState.Queued,
                    Priority      = JobPriority.Normal,
                    HasChildrens  = false,
                    GridCost      = 40,
                    Environment   = @"\\srvrbxassufp01\hpc\Cas04\4-Omen",
                    CreateTime    = _now.AddMinutes(-15),
                    SubmitTime    = _now.AddMinutes(-14),
                    ChangeTime    = _now.AddMinutes(-14)
                },
                new JobItem
                {
                    Id            = 1045,
                    Name          = "UFX_export_2023Q4",
                    UserAccountId = "aleblanc",
                    UserName      = "aleblanc",
                    Progress      = 0,
                    State         = JobState.Failed,
                    Priority      = JobPriority.BelowNormal,
                    HasChildrens  = false,
                    GridCost      = 1,
                    Environment   = @"\\srvrbxassufp01\hpc\Cas05\4-Omen",
                    CreateTime    = _now.AddHours(-3),
                    SubmitTime    = _now.AddHours(-3).AddMinutes(1),
                    ChangeTime    = _now.AddHours(-3).AddMinutes(10)
                },
                new JobItem
                {
                    Id            = 1046,
                    Name          = "Savings_2022Y_stress_all",
                    UserAccountId = "mmartin",
                    UserName      = "mmartin",
                    Progress      = 38,
                    State         = JobState.Running,
                    Priority      = JobPriority.AboveNormal,
                    HasChildrens  = true,
                    GridCost      = 500,
                    Environment   = @"\\srvrbxassufp01\hpc\Cas02\4-Omen",
                    CreateTime    = _now.AddMinutes(-40),
                    SubmitTime    = _now.AddMinutes(-39),
                    ChangeTime    = _now.AddMinutes(-2)
                }
            ]
        };

        return Ok(response);
    }

    /// <summary>Returns the child job groups (execution phases) for a parent job.</summary>
    [HttpGet("jobs/children")]
    [ProducesResponseType(typeof(JobChildrenResponse), StatusCodes.Status200OK)]
    public IActionResult GetJobChildren([FromQuery] int jobId)
    {
        var groups = jobId switch
        {
            1042 => new List<JobGroup>
            {
                new JobGroup
                {
                    Id               = 1, Name = "Initialisation", Status = ChildJobState.Finished,
                    Progress         = 100, Updated = _now.AddHours(-5).AddMinutes(10), ParentId = jobId,
                    LaunchedJobCount = 2,
                    Children         =
                    [
                        new ChildJob { Id = 10421, State = ChildJobState.Finished, Name = "InputGeneration",      Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-5), Submitted = _now.AddHours(-5).AddSeconds(30) },
                        new ChildJob { Id = 10422, State = ChildJobState.Finished, Name = "ScenarioPreparation",  Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-5), Submitted = _now.AddHours(-5).AddMinutes(2) }
                    ]
                },
                new JobGroup
                {
                    Id               = 2, Name = "Calcul déterministe", Status = ChildJobState.Finished,
                    Progress         = 100, Updated = _now.AddHours(-3), ParentId = jobId,
                    LaunchedJobCount = 4,
                    Children         =
                    [
                        new ChildJob { Id = 10423, State = ChildJobState.Finished, Name = "DET_central",     Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-5).AddMinutes(12), Submitted = _now.AddHours(-5).AddMinutes(13) },
                        new ChildJob { Id = 10424, State = ChildJobState.Finished, Name = "DET_stress_up",   Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-5).AddMinutes(12), Submitted = _now.AddHours(-5).AddMinutes(13) },
                        new ChildJob { Id = 10425, State = ChildJobState.Finished, Name = "DET_stress_down", Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-5).AddMinutes(12), Submitted = _now.AddHours(-5).AddMinutes(14) },
                        new ChildJob { Id = 10426, State = ChildJobState.Finished, Name = "DET_lapse",       Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-5).AddMinutes(12), Submitted = _now.AddHours(-5).AddMinutes(14) }
                    ]
                },
                new JobGroup
                {
                    Id               = 3, Name = "Calcul stochastique", Status = ChildJobState.Finished,
                    Progress         = 100, Updated = _now.AddHours(-2), ParentId = jobId,
                    LaunchedJobCount = 2,
                    Children         =
                    [
                        new ChildJob { Id = 10427, State = ChildJobState.Finished, Name = "STO_central",   Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-3).AddMinutes(5), Submitted = _now.AddHours(-3).AddMinutes(6) },
                        new ChildJob { Id = 10428, State = ChildJobState.Finished, Name = "STO_stress_up", Progress = 100, Priority = JobPriority.Normal, Created = _now.AddHours(-3).AddMinutes(5), Submitted = _now.AddHours(-3).AddMinutes(6) }
                    ]
                }
            },
            1043 => new List<JobGroup>
            {
                new JobGroup
                {
                    Id               = 1, Name = "Préparation", Status = ChildJobState.Finished,
                    Progress         = 100, Updated = _now.AddHours(-1).AddMinutes(15), ParentId = jobId,
                    LaunchedJobCount = 1,
                    Children         =
                    [
                        new ChildJob { Id = 10431, State = ChildJobState.Finished, Name = "InputGeneration", Progress = 100, Priority = JobPriority.High, Created = _now.AddHours(-1), Submitted = _now.AddHours(-1).AddMinutes(1) }
                    ]
                },
                new JobGroup
                {
                    Id               = 2, Name = "Calcul principal", Status = ChildJobState.Running,
                    Progress         = 72, Updated = _now.AddMinutes(-5), ParentId = jobId,
                    LaunchedJobCount = 3,
                    Children         =
                    [
                        new ChildJob { Id = 10432, State = ChildJobState.Finished, Name = "NonLife_Seg1", Progress = 100, Priority = JobPriority.High, Created = _now.AddHours(-1).AddMinutes(20), Submitted = _now.AddHours(-1).AddMinutes(21) },
                        new ChildJob { Id = 10433, State = ChildJobState.Running,  Name = "NonLife_Seg2", Progress = 65,  Priority = JobPriority.High, Created = _now.AddHours(-1).AddMinutes(20), Submitted = _now.AddHours(-1).AddMinutes(21) },
                        new ChildJob { Id = 10434, State = ChildJobState.Queued,   Name = "NonLife_Seg3", Progress = 0,   Priority = JobPriority.High, Created = _now.AddHours(-1).AddMinutes(20), Submitted = _now.AddHours(-1).AddMinutes(21) }
                    ]
                }
            },
            1046 => new List<JobGroup>
            {
                new JobGroup
                {
                    Id               = 1, Name = "Initialisation", Status = ChildJobState.Finished,
                    Progress         = 100, Updated = _now.AddMinutes(-35), ParentId = jobId,
                    LaunchedJobCount = 2,
                    Children         =
                    [
                        new ChildJob { Id = 10461, State = ChildJobState.Finished, Name = "InputGeneration",     Progress = 100, Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-40), Submitted = _now.AddMinutes(-39) },
                        new ChildJob { Id = 10462, State = ChildJobState.Finished, Name = "ScenarioPreparation", Progress = 100, Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-40), Submitted = _now.AddMinutes(-39) }
                    ]
                },
                new JobGroup
                {
                    Id               = 2, Name = "Calcul", Status = ChildJobState.Running,
                    Progress         = 38, Updated = _now.AddMinutes(-2), ParentId = jobId,
                    LaunchedJobCount = 5,
                    Children         =
                    [
                        new ChildJob { Id = 10463, State = ChildJobState.Finished, Name = "DET_central",     Progress = 100, Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-30), Submitted = _now.AddMinutes(-30) },
                        new ChildJob { Id = 10464, State = ChildJobState.Running,  Name = "DET_stress_up",   Progress = 55,  Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-30), Submitted = _now.AddMinutes(-30) },
                        new ChildJob { Id = 10465, State = ChildJobState.Running,  Name = "DET_stress_down", Progress = 40,  Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-30), Submitted = _now.AddMinutes(-29) },
                        new ChildJob { Id = 10466, State = ChildJobState.Queued,   Name = "STO_central",     Progress = 0,   Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-30), Submitted = _now.AddMinutes(-29) },
                        new ChildJob { Id = 10467, State = ChildJobState.Queued,   Name = "STO_stress_up",   Progress = 0,   Priority = JobPriority.AboveNormal, Created = _now.AddMinutes(-30), Submitted = _now.AddMinutes(-29) }
                    ]
                }
            },
            _ => new List<JobGroup>()
        };

        return Ok(new JobChildrenResponse { Status = "ok", JobId = jobId, JobGroups = groups });
    }

    /// <summary>Returns the task-level log for a leaf job.</summary>
    [HttpGet("jobs/{jobId}/tasks")]
    [ProducesResponseType(typeof(JobTasksResponse), StatusCodes.Status200OK)]
    public IActionResult GetJobTasks(int jobId)
    {
        var basePath = jobId switch
        {
            1044  => @"\\srvrbxassufp01\hpc\Cas04\4-Omen\",
            1045  => @"\\srvrbxassufp01\hpc\Cas05\4-Omen\",
            10421 => @"\\srvrbxassufp01\hpc\Cas01\4-Omen\input\",
            10422 => @"\\srvrbxassufp01\hpc\Cas01\4-Omen\scenario\",
            10431 => @"\\srvrbxassufp01\hpc\Cas03\4-Omen\input\",
            _     => @"\\srvrbxassufp01\hpc\Cas01\4-Omen\"
        };

        var tasks = jobId switch
        {
            1044 => new List<JobTask>
            {
                new JobTask { Id = 1, State = JobState.Queued, Command = basePath + "run.exe --job risklife --env Cas04", Output = null, StartTime = null, EndTime = null }
            },
            1045 => new List<JobTask>
            {
                new JobTask { Id = 1, State = JobState.Failed, Command = basePath + "ufx_export.exe --source Cas05 --dest output", Output = "ERROR: Connection timeout after 30s\nCould not reach remote host srvrbxassufp01\nCheck network connectivity.", StartTime = _now.AddHours(-3).AddMinutes(2), EndTime = _now.AddHours(-3).AddMinutes(12) }
            },
            10421 => new List<JobTask>
            {
                new JobTask { Id = 1, State = JobState.Finished, Command = basePath + "gen_input.exe --env Cas01 --input Input23.01.00_2022Y_vfinale",    Output = "Input generation completed.\n200 portfolios processed.", StartTime = _now.AddHours(-5),              EndTime = _now.AddHours(-5).AddMinutes(8) },
                new JobTask { Id = 2, State = JobState.Finished, Command = basePath + "validate_input.exe --strict",                                       Output = "Validation OK. No errors.",                                StartTime = _now.AddHours(-5).AddMinutes(8), EndTime = _now.AddHours(-5).AddMinutes(9) }
            },
            10422 => new List<JobTask>
            {
                new JobTask { Id = 1, State = JobState.Finished, Command = basePath + "prep_scenario.exe --num 1 --name central",    Output = "Scenario 1 (central) prepared.",    StartTime = _now.AddHours(-5).AddMinutes(2), EndTime = _now.AddHours(-5).AddMinutes(5) },
                new JobTask { Id = 2, State = JobState.Finished, Command = basePath + "prep_scenario.exe --num 2 --name stress_up",  Output = "Scenario 2 (stress_up) prepared.",  StartTime = _now.AddHours(-5).AddMinutes(5), EndTime = _now.AddHours(-5).AddMinutes(8) },
                new JobTask { Id = 3, State = JobState.Finished, Command = basePath + "prep_scenario.exe --num 3 --name stress_down",Output = "Scenario 3 (stress_down) prepared.",StartTime = _now.AddHours(-5).AddMinutes(8), EndTime = _now.AddHours(-5).AddMinutes(10) }
            },
            10431 => new List<JobTask>
            {
                new JobTask { Id = 1, State = JobState.Finished, Command = basePath + "gen_input.exe --env Cas03 --input Input_NonLife_2023Y", Output = "NonLife input generated. 50 segments loaded.", StartTime = _now.AddHours(-1).AddMinutes(2), EndTime = _now.AddHours(-1).AddMinutes(14) }
            },
            _ => new List<JobTask>
            {
                new JobTask { Id = 1, State = JobState.Finished, Command = basePath + "compute.exe --jobId " + jobId, Output = "Computation finished successfully.", StartTime = _now.AddHours(-2), EndTime = _now.AddHours(-1) }
            }
        };

        return Ok(new JobTasksResponse { Status = "ok", JobId = jobId, Tasks = tasks });
    }

    /// <summary>Cancels a running or queued job.</summary>
    [HttpPost("cancel")]
    [ProducesResponseType(typeof(StatusMessageResponse), StatusCodes.Status200OK)]
    public IActionResult CancelJob([FromBody] JobActionRequest request)
        => Ok(new StatusMessageResponse { Status = "ok", Message = $"Job {request.JobId} cancelled." });

    /// <summary>Requeues a failed or cancelled job.</summary>
    [HttpPost("requeue")]
    [ProducesResponseType(typeof(StatusMessageResponse), StatusCodes.Status200OK)]
    public IActionResult RequeueJob([FromBody] JobActionRequest request)
        => Ok(new StatusMessageResponse { Status = "ok", Message = $"Job {request.JobId} requeued." });
}
