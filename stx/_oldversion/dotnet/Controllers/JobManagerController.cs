using Microsoft.AspNetCore.Mvc;
using Styx.Models.Entities;
using Styx.Models.Enums;
using Styx.Models.Requests;
using Styx.Models.Responses;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class JobManagerController : ControllerBase
{
    // ── Shared fake data ─────────────────────────────────────────────────────

    private static readonly List<ModelEntry> _savingsModels =
    [
        new ModelEntry { Model = "OMEN_S2_v23",  Versions = ["23.01.00", "23.02.00", "23.03.00"] },
        new ModelEntry { Model = "OMEN_S2_v22",  Versions = ["22.04.00", "22.05.00"] },
        new ModelEntry { Model = "OMEN_S1_v23",  Versions = ["23.01.00"] },
        new ModelEntry { Model = "OMEN_FR_v22",  Versions = ["22.01.00", "22.02.00"] }
    ];

    private static readonly List<ModelEntry> _nonLifeModels =
    [
        new ModelEntry { Model = "OMEN_NL_v23", Versions = ["23.01.00", "23.02.00"] },
        new ModelEntry { Model = "OMEN_NL_v22", Versions = ["22.03.00"] }
    ];

    private static readonly List<ModelEntry> _riskLifeModels =
    [
        new ModelEntry { Model = "OMEN_RL_v23",    Versions = ["23.01.00", "23.02.00"] },
        new ModelEntry { Model = "OMEN_RL_KP_v23", Versions = ["23.01.00"] }
    ];

    private static readonly List<ModelEntry> _tdrModels =
    [
        new ModelEntry { Model = "TDR_v23", Versions = ["23.01.00"] },
        new ModelEntry { Model = "TDR_v22", Versions = ["22.01.00", "22.02.00"] }
    ];

    private static readonly List<ModelEntry> _brdModels =
    [
        new ModelEntry { Model = "BRD_v23", Versions = ["23.01.00"] },
        new ModelEntry { Model = "BRD_v22", Versions = ["22.01.00"] }
    ];

    // ── Init ─────────────────────────────────────────────────────────────────

    /// <summary>Savings (Omen Épargne) — initialisation data.</summary>
    [HttpGet("savings/init")]
    [ProducesResponseType(typeof(SavingsInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetSavingsInit()
        => Ok(new SavingsInitResponse
        {
            Status                        = "ok",
            DefaultName                   = "Savings_2022Y",
            DetChecked                    = true,
            StoChecked                    = true,
            DefaultDetPeriodSim           = 12,
            DefaultDetIterations          = "1-2000",
            DefaultStoPeriodSim           = 12,
            DefaultStoIterations          = "1-2000",
            DefaultPricerPeriodSim        = 12,
            DefaultPricerIterations       = "1-2000",
            Models                        = _savingsModels,
            TaskTypes                     = [TaskType.Full, TaskType.Deterministic, TaskType.Stochastic, TaskType.InputOnly],
            DefaultTaskType               = TaskType.Full,
            Priorities                    = [JobPriority.Normal, JobPriority.High, JobPriority.BelowNormal, JobPriority.AboveNormal, JobPriority.Automatic],
            DefaultJobPriority            = JobPriority.Normal,
            JobOmenTypes                  = [OmenType.S2, OmenType.S1, OmenType.FR_GAAP, OmenType.Solvency_II],
            DefaultJobType                = OmenType.S2,
            DefaultIsGuaranteedFloorChecked = false,
            DefaultIsTrdPricerEnabled     = false
        });

    /// <summary>NonLife (Omen Non-Vie) — initialisation data.</summary>
    [HttpGet("nonlife/init")]
    [ProducesResponseType(typeof(SimpleInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetNonLifeInit()
        => Ok(new SimpleInitResponse
        {
            Status        = "ok",
            DefaultName   = "NonLife_2022Y",
            DefaultPeriod = 12,
            Models        = _nonLifeModels
        });

    /// <summary>TdR (Taux de Rendement) — initialisation data.</summary>
    [HttpGet("tdr/init")]
    [ProducesResponseType(typeof(SimpleInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetTdrInit()
        => Ok(new SimpleInitResponse
        {
            Status        = "ok",
            DefaultName   = "TdR_2022Y",
            DefaultPeriod = 12,
            Models        = _tdrModels
        });

    /// <summary>BRD — initialisation data.</summary>
    [HttpGet("brd/init")]
    [ProducesResponseType(typeof(BrdInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetBrdInit()
        => Ok(new BrdInitResponse
        {
            Status                    = "ok",
            DefaultName               = "BRD_2022Y",
            DefaultProjectionDuration = 30,
            Models                    = _brdModels
        });

    /// <summary>RiskLife — initialisation data.</summary>
    [HttpGet("risklife/init")]
    [ProducesResponseType(typeof(RiskLifeInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetRiskLifeInit()
        => Ok(new RiskLifeInitResponse
        {
            Status               = "ok",
            DefaultName          = "RiskLife_2022Y",
            DefaultIterations    = "1-1",
            DefaultAutoIterations= false,
            DefaultPeriod        = 12,
            Models               = _riskLifeModels,
            JobOmenTypes         = [OmenType.S2, OmenType.S1, OmenType.FR_GAAP],
            DefaultJobType       = OmenType.S2,
            Scenarios            =
            [
                new RLScenarioEntry { Num = 1,  Name = "Central",       Selected = true  },
                new RLScenarioEntry { Num = 2,  Name = "Rate up",       Selected = false },
                new RLScenarioEntry { Num = 3,  Name = "Rate down",     Selected = false },
                new RLScenarioEntry { Num = 4,  Name = "Lapse mass",    Selected = false },
                new RLScenarioEntry { Num = 5,  Name = "Mortality up",  Selected = false }
            ]
        });

    /// <summary>RiskLifeKP — initialisation data (same shape as RiskLife; defaultAutoIterations = true).</summary>
    [HttpGet("risklifekp/init")]
    [ProducesResponseType(typeof(RiskLifeInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetRiskLifeKpInit()
        => Ok(new RiskLifeInitResponse
        {
            Status               = "ok",
            DefaultName          = "RiskLifeKP_2022Y",
            DefaultIterations    = "1-1",
            DefaultAutoIterations= true,
            DefaultPeriod        = 12,
            Models               = _riskLifeModels,
            JobOmenTypes         = [OmenType.S2, OmenType.S1],
            DefaultJobType       = OmenType.S2,
            Scenarios            =
            [
                new RLScenarioEntry { Num = 1, Name = "Central",    Selected = true  },
                new RLScenarioEntry { Num = 2, Name = "Rate up",    Selected = false },
                new RLScenarioEntry { Num = 3, Name = "Rate down",  Selected = false }
            ]
        });

    /// <summary>Scenario Transformator — initialisation data.</summary>
    [HttpGet("scenarioTransfo/init")]
    [ProducesResponseType(typeof(ScenarioTransfoInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetScenarioTransfoInit()
        => Ok(new ScenarioTransfoInitResponse
        {
            ModelTypes        =
            [
                new LabelValueEntry { Value = "2017", Label = "Model 2017" },
                new LabelValueEntry { Value = "2018", Label = "Model 2018" },
                new LabelValueEntry { Value = "2020", Label = "Model 2020" },
                new LabelValueEntry { Value = "V2",   Label = "Model V2"   }
            ],
            DefaultModelType  = "2020",
            Periodes          =
            [
                new LabelValueEntry { Value = "Mois",  Label = "Mensuel" },
                new LabelValueEntry { Value = "Annee", Label = "Annuel"  }
            ],
            DefaultPeriode    = "Annee",
            Iterations        = [100, 500, 1000, 2000, 5000],
            DefaultIterations = 1000,
            Coupons           = ["0%", "1%", "2%", "3%", "4%", "5%"],
            DefaultCoupon     = "2%"
        });

    // ── Inputs ───────────────────────────────────────────────────────────────

    /// <summary>Returns the static reference input-folder catalogue.</summary>
    [HttpGet("inputs")]
    [ProducesResponseType(typeof(IEnumerable<string>), StatusCodes.Status200OK)]
    public IActionResult GetInputs()
        => Ok(new List<string>
        {
            "Input23.01.00_2022Y_vfinale",
            "Input23.01.00_2022Y_vfinale_2021",
            "Input23.01.00_2022Y_vfinale_2022",
            "Input23.01.00_2022Y_vfinale_cible",
            "Input23.01.00_2022Y_vfinale_pgg1",
            "Input23.01.00_2022Y_vfinale_pgg2",
            "Input_NonLife_2022Y",
            "Input_NonLife_2023Y",
            "Input_RiskLife_2022Y",
            "Input_TdR_2022Y",
            "Input_final_KP",
            "Input_Gap"
        });

    /// <summary>Refreshes the input-folder list for a given environment path.</summary>
    [HttpGet("refreshinputs")]
    [ProducesResponseType(typeof(RefreshInputsResponse), StatusCodes.Status200OK)]
    public IActionResult RefreshInputs([FromQuery] string? environment)
        => Ok(new RefreshInputsResponse
        {
            Inputs =
            [
                "Input23.01.00_2022Y_vfinale",
                "Input23.01.00_2022Y_vfinale_2022",
                "Input23.01.00_2022Y_vfinale_cible",
                "Input23.01.00_2022Y_vfinale_pgg1"
            ]
        });

    /// <summary>Returns the model/version catalogue for Savings.</summary>
    [HttpGet("savings/models/versions")]
    [ProducesResponseType(typeof(ModelVersionsResponse), StatusCodes.Status200OK)]
    public IActionResult GetSavingsModelVersions()
        => Ok(new ModelVersionsResponse
        {
            Model    = "OMEN_S2_v23",
            Versions = ["23.01.00", "23.02.00", "23.03.00"]
        });

    /// <summary>Returns the scenario library for Savings.</summary>
    [HttpGet("savings/models/scenarios")]
    [ProducesResponseType(typeof(IEnumerable<ScenarioDescriptor>), StatusCodes.Status200OK)]
    public IActionResult GetSavingsScenarios()
        => Ok(new List<ScenarioDescriptor>
        {
            new ScenarioDescriptor { ScenarioNum = 1, CalVif = "central",     Description = "Central scenario",  IsScenarioSelected = true,  IsEnabled = true,  Depth = 0, Filename = "scenario_central.csv",     FilenameDot = "scenario_central.dot",     FilenameSp = "scenario_central.sp",     FilenameL = [], FilenameDotL = [], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
            new ScenarioDescriptor { ScenarioNum = 2, CalVif = "stress_up",   Description = "Rate up stress",    IsScenarioSelected = false, IsEnabled = true,  Depth = 0, Filename = "scenario_stress_up.csv",   FilenameDot = "scenario_stress_up.dot",   FilenameSp = null,                      FilenameL = [], FilenameDotL = [], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
            new ScenarioDescriptor { ScenarioNum = 3, CalVif = "stress_down", Description = "Rate down stress",  IsScenarioSelected = false, IsEnabled = true,  Depth = 0, Filename = "scenario_stress_down.csv", FilenameDot = "scenario_stress_down.dot", FilenameSp = null,                      FilenameL = [], FilenameDotL = [], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
            new ScenarioDescriptor { ScenarioNum = 4, CalVif = "lapse_mass",  Description = "Mass lapse",        IsScenarioSelected = false, IsEnabled = false, Depth = 0, Filename = "scenario_lapse_mass.csv",  FilenameDot = null,                       FilenameSp = null,                      FilenameL = [], FilenameDotL = [], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
            new ScenarioDescriptor { ScenarioNum = 5, CalVif = "mortality_up",Description = "Mortality up",      IsScenarioSelected = false, IsEnabled = true,  Depth = 0, Filename = "scenario_mortality_up.csv",FilenameDot = null,                       FilenameSp = null,                      FilenameL = [], FilenameDotL = [], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] }
        });

    // ── Submit ───────────────────────────────────────────────────────────────

    private static SubmitResponse FakeSubmitResponse(int parentId = 10050, int count = 4)
        => new SubmitResponse
        {
            ParentId         = parentId,
            LaunchedJobCount = count,
            ApiResults       = new ApiResults
            {
                LightGridSubmissionResult =
                [
                    new LightGridResult
                    {
                        JobId    = parentId,
                        TasksIds = [new TaskIdEntry { Id = 1, GridId = 5001 }, new TaskIdEntry { Id = 2, GridId = 5002 }]
                    }
                ],
                ExternalApiSubmissionResult = new ExternalApiResult
                {
                    Status = "ok",
                    Ids    = [new ExternalIdEntry { Id = parentId, BpcId = 2001, XGridId = 5001 }]
                }
            }
        };

    /// <summary>Submit a Savings job.</summary>
    [HttpPost("submit/savings")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitSavings([FromBody] SavingsSubmitRequest request)
        => Ok(FakeSubmitResponse(10050, 4));

    /// <summary>Submit a NonLife job.</summary>
    [HttpPost("submit/nonlife")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitNonLife([FromBody] NonLifeSubmitRequest request)
        => Ok(FakeSubmitResponse(10051, 2));

    /// <summary>Submit a RiskLife job.</summary>
    [HttpPost("submit/risklife")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitRiskLife([FromBody] RiskLifeSubmitRequest request)
        => Ok(FakeSubmitResponse(10052, 3));

    /// <summary>Submit a RiskLifeKP job.</summary>
    [HttpPost("submit/risklifekp")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitRiskLifeKp([FromBody] RiskLifeSubmitRequest request)
        => Ok(FakeSubmitResponse(10053, 2));

    /// <summary>Submit a TdR job.</summary>
    [HttpPost("submit/tdr")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitTdr([FromBody] TdrSubmitRequest request)
        => Ok(FakeSubmitResponse(10054, 1));

    /// <summary>Submit a BRD job.</summary>
    [HttpPost("submit/brd")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitBrd([FromBody] BrdSubmitRequest request)
        => Ok(FakeSubmitResponse(10055, 3));

    /// <summary>Submit a UFX job.</summary>
    [HttpPost("submit/ufx")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitUfx([FromBody] UfxSubmitRequest request)
        => Ok(FakeSubmitResponse(10056, 1));

    /// <summary>Submit a Custom Input job.</summary>
    [HttpPost("submit/custominput")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitCustomInput([FromBody] CustomInputSubmitRequest request)
        => Ok(FakeSubmitResponse(10057, 1));

    /// <summary>Submit a Scenario Transformator job.</summary>
    [HttpPost("submit/scenarioTransfo")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitScenarioTransfo([FromBody] ScenarioTransfoSubmitRequest request)
        => Ok(FakeSubmitResponse(10058, 2));
}
