# ============================
# Get-OctopusProjectSteps.ps1
# Lists Octopus projects + step "type" (Deploy to IIS, Deploy a Package, etc.)
# ============================

param(
    [string]$ApiKey = "API-FDPVNVXE7ZPRPOXBNTTCAPEXLNXWBW91",
    [string]$OctopusURL = "https://octopus.world.fluidtechnology.net",
    [string]$OutputFile = ".\Octopus_ProjectSteps_StepTypes.csv"
)

if (-not $ApiKey) {
    Write-Host "ERROR: Missing API key. Run script with -ApiKey <key>" -ForegroundColor Red
    exit 1
}

$header = @{ "X-Octopus-ApiKey" = $ApiKey }

# Optional: get library step templates so vi kan visa deras namn också
Write-Host "Fetching action templates..." -ForegroundColor Cyan
$templates = Invoke-RestMethod -Method GET -Uri "$OctopusURL/api/actiontemplates/all" -Headers $header
$templatesById = @{}
foreach ($t in $templates) {
    $templatesById[$t.Id] = $t.Name
}

# Map ActionType -> friendly name (like in the UI)
$stepTypeMap = @{
    "Octopus.TentaclePackage" = "Deploy a Package"
    "Octopus.IIS"             = "Deploy to IIS"
    "Octopus.WindowsService"  = "Deploy a Windows Service"
    "Octopus.AzureWebApp"     = "Deploy an Azure Web App"
    "Octopus.AzureCloudService" = "Deploy an Azure Cloud Service"
    "Octopus.Script"          = "Run a Script"
}

Write-Host "Fetching projects..." -ForegroundColor Cyan
$projects = Invoke-RestMethod -Method GET -Uri "$OctopusURL/api/projects/all" -Headers $header

$output = @()

foreach ($project in $projects) {

    Write-Host "Processing project: $($project.Name)" -ForegroundColor Yellow

    $proc = Invoke-RestMethod -Method GET `
        -Uri "$OctopusURL/api/deploymentprocesses/$($project.DeploymentProcessId)" `
        -Headers $header

    foreach ($step in $proc.Steps) {
        foreach ($action in $step.Actions) {

            $templateId = $action.Properties["Octopus.Action.Template.Id"]
            $stepTemplateName = $null

            if ($templateId -and $templatesById.ContainsKey($templateId)) {
                # Custom/library step template
                $stepTemplateName = $templatesById[$templateId]
            }
            elseif ($stepTypeMap.ContainsKey($action.ActionType)) {
                # Built-in step mapped to friendly name
                $stepTemplateName = $stepTypeMap[$action.ActionType]
            }
            else {
                # Fallback: show raw ActionType
                $stepTemplateName = $action.ActionType
            }

            $output += [pscustomobject]@{
                ProjectName  = $project.Name
                StepTemplate = $stepTemplateName
            }
        }
    }
}

# Only two columns will be exported
$output | Export-Csv -NoTypeInformation -Path $OutputFile

Write-Host "Done! File created: $OutputFile" -ForegroundColor Green
