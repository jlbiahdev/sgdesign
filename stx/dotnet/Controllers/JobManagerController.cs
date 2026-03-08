using Microsoft.AspNetCore.Mvc;
using Styx.Models.Entities;
using Styx.Models.Requests;
using Styx.Models.Responses;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class JobManagerController : ControllerBase
{
    // ── Init ─────────────────────────────────────────────────────────────────

    /// <summary>Savings (Omen Épargne) — initialisation data.</summary>
    [HttpGet("savings/init")]
    [ProducesResponseType(typeof(SavingsInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetSavingsInit() => throw new NotImplementedException();

    /// <summary>NonLife (Omen Non-Vie) — initialisation data.</summary>
    [HttpGet("nonlife/init")]
    [ProducesResponseType(typeof(SimpleInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetNonLifeInit() => throw new NotImplementedException();

    /// <summary>TdR (Taux de Rendement) — initialisation data.</summary>
    [HttpGet("tdr/init")]
    [ProducesResponseType(typeof(SimpleInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetTdrInit() => throw new NotImplementedException();

    /// <summary>BRD — initialisation data.</summary>
    [HttpGet("brd/init")]
    [ProducesResponseType(typeof(BrdInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetBrdInit() => throw new NotImplementedException();

    /// <summary>RiskLife — initialisation data.</summary>
    [HttpGet("risklife/init")]
    [ProducesResponseType(typeof(RiskLifeInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetRiskLifeInit() => throw new NotImplementedException();

    /// <summary>RiskLifeKP — initialisation data (same shape as RiskLife; defaultAutoIterations = true).</summary>
    [HttpGet("risklifekp/init")]
    [ProducesResponseType(typeof(RiskLifeInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetRiskLifeKpInit() => throw new NotImplementedException();

    /// <summary>Scenario Transformator — initialisation data.</summary>
    [HttpGet("scenarioTransfo/init")]
    [ProducesResponseType(typeof(ScenarioTransfoInitResponse), StatusCodes.Status200OK)]
    public IActionResult GetScenarioTransfoInit() => throw new NotImplementedException();

    // ── Inputs ───────────────────────────────────────────────────────────────

    /// <summary>Returns the static reference input-folder catalogue.</summary>
    [HttpGet("inputs")]
    [ProducesResponseType(typeof(IEnumerable<string>), StatusCodes.Status200OK)]
    public IActionResult GetInputs() => throw new NotImplementedException();

    /// <summary>Refreshes the input-folder list for a given environment path.</summary>
    [HttpGet("refreshinputs")]
    [ProducesResponseType(typeof(RefreshInputsResponse), StatusCodes.Status200OK)]
    public IActionResult RefreshInputs([FromQuery] string? environment) => throw new NotImplementedException();

    /// <summary>Returns the model/version catalogue for Savings.</summary>
    [HttpGet("savings/models/versions")]
    [ProducesResponseType(typeof(ModelVersionsResponse), StatusCodes.Status200OK)]
    public IActionResult GetSavingsModelVersions() => throw new NotImplementedException();

    /// <summary>Returns the scenario library for Savings.</summary>
    [HttpGet("savings/models/scenarios")]
    [ProducesResponseType(typeof(IEnumerable<ScenarioDescriptor>), StatusCodes.Status200OK)]
    public IActionResult GetSavingsScenarios() => throw new NotImplementedException();

    // ── Submit ───────────────────────────────────────────────────────────────

    /// <summary>Submit a Savings job.</summary>
    [HttpPost("submit/savings")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitSavings([FromBody] SavingsSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a NonLife job.</summary>
    [HttpPost("submit/nonlife")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitNonLife([FromBody] NonLifeSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a RiskLife job.</summary>
    [HttpPost("submit/risklife")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitRiskLife([FromBody] RiskLifeSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a RiskLifeKP job.</summary>
    [HttpPost("submit/risklifekp")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitRiskLifeKp([FromBody] RiskLifeSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a TdR job.</summary>
    [HttpPost("submit/tdr")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitTdr([FromBody] TdrSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a BRD job.</summary>
    [HttpPost("submit/brd")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitBrd([FromBody] BrdSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a UFX job.</summary>
    [HttpPost("submit/ufx")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitUfx([FromBody] UfxSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a Custom Input job.</summary>
    [HttpPost("submit/custominput")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitCustomInput([FromBody] CustomInputSubmitRequest request) => throw new NotImplementedException();

    /// <summary>Submit a Scenario Transformator job.</summary>
    [HttpPost("submit/scenarioTransfo")]
    [ProducesResponseType(typeof(SubmitResponse), StatusCodes.Status200OK)]
    public IActionResult SubmitScenarioTransfo([FromBody] ScenarioTransfoSubmitRequest request) => throw new NotImplementedException();
}
