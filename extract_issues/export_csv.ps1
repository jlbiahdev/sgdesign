# Télécharge tous les tickets du projet et les exporte en CSV
$base  = "https://<ton-gitlab>/api/v4/projects/2484/issues"
$token = Read-Host "Token GitLab"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$issues = @()
$page = 1
do {
    $url   = "$($base)?state=all&per_page=100&page=$page"
    $resp  = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ "PRIVATE-TOKEN" = $token }
    $json  = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    $batch = @($json | ConvertFrom-Json | ForEach-Object { $_ })
    $issues += $batch
    Write-Host "Page $page : $($batch.Count) tickets"
    $page++
} while ($batch.Count -eq 100)

$issues |
    Sort-Object { $_.milestone.title }, iid |
    Select-Object @{n='jalon';       e={$_.milestone.title}},
                  @{n='jalon_url';   e={$_.milestone.web_url}},
                  @{n='issue_iid';   e={$_.iid}},
                  @{n='issue_title'; e={$_.title}} |
    Export-Csv -Path "extracts\issues.csv" -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Host "$($issues.Count) tickets exportés dans extracts\issues.csv"