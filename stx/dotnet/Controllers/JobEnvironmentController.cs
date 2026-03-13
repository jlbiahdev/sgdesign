using Microsoft.AspNetCore.Mvc;
using Styx.Models.Entities;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class JobEnvironmentController : ControllerBase
{
    // Fake UNC tree keyed by normalised relative path (forward slashes, no leading slash).
    private static readonly Dictionary<string, TreeNode> _tree = new()
    {
        [""] = new TreeNode { Folders = ["hpc"], Files = [] },

        ["hpc"] = new TreeNode { Folders = ["Cas01", "Cas02", "Cas03", "Cas04", "Cas05"], Files = [] },

        ["hpc/Cas01"]        = new TreeNode { Folders = ["4-Omen"], Files = [] },
        ["hpc/Cas01/4-Omen"] = new TreeNode { Folders = ["input", "output", "scenario"], Files = [] },

        ["hpc/Cas01/4-Omen/input"] = new TreeNode
        {
            Folders =
            [
                "04_Dividendes_v2",
                "Input23.01.00_2022Y_vfinale",
                "Input23.01.00_2022Y_vfinale - Copy",
                "Input23.01.00_2022Y_vfinale_2021",
                "Input23.01.00_2022Y_vfinale_2022",
                "Input23.01.00_2022Y_vfinale_2023",
                "Input23.01.00_2022Y_vfinale_2024",
                "Input23.01.00_2022Y_vfinale_2025",
                "Input23.01.00_2022Y_vfinale_2026",
                "Input23.01.00_2022Y_vfinale_cible",
                "Input23.01.00_2022Y_vfinale_pgg1",
                "Input23.01.00_2022Y_vfinale_pgg2",
                "Input_EBA2021_adverse_v9_init_alloc",
                "Input_final_KP",
                "Input_Gap"
            ],
            Files = []
        },
        ["hpc/Cas01/4-Omen/input/Input23.01.00_2022Y_vfinale"] = new TreeNode
        {
            Folders = [],
            Files   = ["portfolio.xml", "params_savings.json", "hypotheses.csv", "mapping.xlsx"]
        },
        ["hpc/Cas01/4-Omen/input/Input23.01.00_2022Y_vfinale_cible"] = new TreeNode
        {
            Folders = [],
            Files   = ["portfolio.xml", "params_savings.json", "hypotheses.csv"]
        },
        ["hpc/Cas01/4-Omen/input/Input23.01.00_2022Y_vfinale_pgg1"] = new TreeNode
        {
            Folders = [],
            Files   = ["portfolio.xml", "params_savings.json"]
        },
        ["hpc/Cas01/4-Omen/input/Input23.01.00_2022Y_vfinale_pgg2"] = new TreeNode
        {
            Folders = [],
            Files   = ["portfolio.xml", "params_savings.json"]
        },

        ["hpc/Cas01/4-Omen/output"] = new TreeNode
        {
            Folders = ["2022Y_run01", "2022Y_run02"],
            Files   = []
        },
        ["hpc/Cas01/4-Omen/output/2022Y_run01"] = new TreeNode
        {
            Folders = [],
            Files   = ["output_central.csv", "output_stress_up.csv", "output_stress_down.csv", "summary.xlsx"]
        },
        ["hpc/Cas01/4-Omen/output/2022Y_run02"] = new TreeNode
        {
            Folders = [],
            Files   = ["output_central.csv", "output_stress_up.csv", "summary.xlsx"]
        },

        ["hpc/Cas01/4-Omen/scenario"] = new TreeNode
        {
            Folders   = [],
            Files     = [],
            Scenarios =
            [
                new ScenarioDescriptor { ScenarioNum = 1, CalVif = "central",     Description = "Central scenario",  IsScenarioSelected = true,  IsEnabled = true,  Depth = 0, Filename = "scenario_central.csv",      FilenameDot = "scenario_central.dot",     FilenameSp = "scenario_central.sp",     FilenameL = ["scenario_central_l1.csv", "scenario_central_l2.csv"], FilenameDotL = ["scenario_central_l1.dot"], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
                new ScenarioDescriptor { ScenarioNum = 2, CalVif = "stress_up",   Description = "Rate up stress",    IsScenarioSelected = false, IsEnabled = true,  Depth = 0, Filename = "scenario_stress_up.csv",    FilenameDot = "scenario_stress_up.dot",   FilenameSp = null,                      FilenameL = ["scenario_stress_up_l1.csv"],                          FilenameDotL = [],                          FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
                new ScenarioDescriptor { ScenarioNum = 3, CalVif = "stress_down", Description = "Rate down stress",  IsScenarioSelected = false, IsEnabled = true,  Depth = 0, Filename = "scenario_stress_down.csv",  FilenameDot = "scenario_stress_down.dot", FilenameSp = null,                      FilenameL = ["scenario_stress_down_l1.csv"],                        FilenameDotL = [],                          FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
                new ScenarioDescriptor { ScenarioNum = 4, CalVif = "lapse_mass",  Description = "Mass lapse",        IsScenarioSelected = false, IsEnabled = false, Depth = 0, Filename = "scenario_lapse_mass.csv",   FilenameDot = null,                       FilenameSp = null,                      FilenameL = [],                                                     FilenameDotL = [],                          FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] },
                new ScenarioDescriptor { ScenarioNum = 5, CalVif = "mortality_up",Description = "Mortality up",      IsScenarioSelected = false, IsEnabled = true,  Depth = 0, Filename = "scenario_mortality_up.csv", FilenameDot = null,                       FilenameSp = null,                      FilenameL = [],                                                     FilenameDotL = [],                          FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] }
            ]
        },

        ["hpc/Cas02"]        = new TreeNode { Folders = ["4-Omen"], Files = [] },
        ["hpc/Cas02/4-Omen"] = new TreeNode { Folders = ["input", "output", "scenario"], Files = [] },
        ["hpc/Cas02/4-Omen/input"] = new TreeNode
        {
            Folders = ["Input23.01.00_2022Y_KP", "Input23.02.00_2023Y_vfinale"],
            Files   = []
        },
        ["hpc/Cas02/4-Omen/output"]  = new TreeNode { Folders = ["2023Y_run01"], Files = [] },
        ["hpc/Cas02/4-Omen/scenario"] = new TreeNode
        {
            Folders = [], Files = [],
            Scenarios =
            [
                new ScenarioDescriptor { ScenarioNum = 1, CalVif = "central", Description = "Central", IsScenarioSelected = true, IsEnabled = true, Depth = 0, Filename = "scenario_central.csv", FilenameDot = "scenario_central.dot", FilenameSp = null, FilenameL = [], FilenameDotL = [], FilenameSpL = [], DollFilenameL = [], DollFilenameDotD = [], DollFilenameSpL = [], ListDollarFiles = [] }
            ]
        },

        ["hpc/Cas03"]        = new TreeNode { Folders = ["4-Omen"], Files = [] },
        ["hpc/Cas03/4-Omen"] = new TreeNode { Folders = ["input", "output", "scenario"], Files = [] },
        ["hpc/Cas03/4-Omen/input"]   = new TreeNode { Folders = ["Input_NonLife_2022Y", "Input_NonLife_2023Y"], Files = [] },
        ["hpc/Cas03/4-Omen/output"]  = new TreeNode { Folders = [], Files = [] },
        ["hpc/Cas03/4-Omen/scenario"] = new TreeNode { Folders = [], Files = [], Scenarios = [] },

        ["hpc/Cas04"]        = new TreeNode { Folders = ["4-Omen"], Files = [] },
        ["hpc/Cas04/4-Omen"] = new TreeNode { Folders = ["input", "output", "scenario"], Files = [] },
        ["hpc/Cas04/4-Omen/input"]   = new TreeNode { Folders = ["Input_RiskLife_2022Y"], Files = [] },
        ["hpc/Cas04/4-Omen/output"]  = new TreeNode { Folders = [], Files = [] },
        ["hpc/Cas04/4-Omen/scenario"] = new TreeNode { Folders = [], Files = [], Scenarios = [] },

        ["hpc/Cas05"]        = new TreeNode { Folders = ["4-Omen"], Files = [] },
        ["hpc/Cas05/4-Omen"] = new TreeNode { Folders = ["input", "output", "scenario"], Files = [] },
        ["hpc/Cas05/4-Omen/input"]   = new TreeNode { Folders = ["Input_TdR_2022Y"], Files = [] },
        ["hpc/Cas05/4-Omen/output"]  = new TreeNode { Folders = [], Files = [] },
        ["hpc/Cas05/4-Omen/scenario"] = new TreeNode { Folders = [], Files = [], Scenarios = [] }
    };

    /// <summary>
    /// Explores a single node of the remote UNC filesystem.
    /// <paramref name="rootFolder"/> is the relative path from the UNC root (forward or back slashes).
    /// When <paramref name="isFolder"/> is true the response contains only sub-folders (files list is empty).
    /// </summary>
    [HttpGet("explore")]
    [ProducesResponseType(typeof(TreeNode), StatusCodes.Status200OK)]
    public IActionResult Explore(
        [FromQuery] string? rootFolder,
        [FromQuery] bool    isFolder  = false,
        [FromQuery] string? extension = null)
    {
        // Normalise path: back-slashes → forward, trim leading separator
        var path = (rootFolder ?? string.Empty)
            .Replace('\\', '/')
            .Trim('/');

        _tree.TryGetValue(path, out var node);
        node ??= new TreeNode { Folders = [], Files = [] };

        IEnumerable<string> files = node.Files;

        if (isFolder)
        {
            files = [];
        }
        else if (!string.IsNullOrWhiteSpace(extension))
        {
            var ext = "." + extension.TrimStart('.');
            files = files.Where(f => f.EndsWith(ext, StringComparison.OrdinalIgnoreCase));
        }

        return Ok(new TreeNode
        {
            Folders   = node.Folders,
            Files     = files.ToList(),
            Scenarios = node.Scenarios
        });
    }
}
