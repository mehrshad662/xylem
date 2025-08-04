# Octopus config
$octopusUrl = "https://octopus.world.fluidtechnology.net"
$apiKey = "API-KEMOTGNGR1PQBBI7DUX2SZJ6NWZXDSY" 
$spaceId = "Spaces-1"
$headers = @{ "X-Octopus-ApiKey" = $apiKey }

# Date range
$endDate = Get-Date
$startDate = $endDate.AddDays(-7)

# Get deployments
$deploymentsUrl = "$octopusUrl/api/$spaceId/deployments?skip=0&take=1000"
$deployments = Invoke-RestMethod -Uri $deploymentsUrl -Headers $headers
$recentDeployments = $deployments.Items | Where-Object {
    $deployDate = Get-Date($_.Created)
    $deployDate -ge $startDate -and $deployDate -le $endDate
}

# Prepare data
$successCount = 0
$failedCount = 0
$deploymentData = @()

foreach ($deployment in $recentDeployments) {
    try {
        $task = Invoke-RestMethod -Uri "$octopusUrl/api/$spaceId/tasks/$($deployment.TaskId)" -Headers $headers
        $project = Invoke-RestMethod -Uri "$octopusUrl/api/$spaceId/projects/$($deployment.ProjectId)" -Headers $headers
        $env = Invoke-RestMethod -Uri "$octopusUrl/api/$spaceId/environments/$($deployment.EnvironmentId)" -Headers $headers
    } catch {
        Write-Host "`n❌ Failed to fetch deployment data: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $status = $task.State
    if ($status -eq "Success") { $successCount++ }
    elseif ($status -eq "Failed") { $failedCount++ }

    $deploymentData += [PSCustomObject]@{
        Project      = $project.Name
        Environment  = $env.Name
        DeploymentAt = $task.CompletedTime
        Result       = $status
    }
}

# === Manual CSV Export ===
$csvPath = ".\deployments.csv"

# Write summary
@(
    "Summary,Value"
    "Successful deployments,$successCount"
    "Failed deployments,$failedCount"
    ""
    "Project,Environment,DeploymentAt,Result"
) | Out-File -FilePath $csvPath -Encoding UTF8

# Append each deployment line manually
foreach ($d in $deploymentData) {
    "$($d.Project),$($d.Environment),`"$($d.DeploymentAt)`",$($d.Result)" | Add-Content -Path $csvPath
}

# Done!
Write-Host "`n✅ Done! CSV with summary and deployments saved as '$csvPath'" -ForegroundColor Green
