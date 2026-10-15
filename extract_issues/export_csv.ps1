# Convertit les fichiers issues_*.json en issues.csv (séparateur ;)
$issues = Get-ChildItem -Path "issues_*.json" | ForEach-Object {
    Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
} | ForEach-Object { $_ }

$issues |
    Sort-Object { $_.milestone.title }, iid |
    Select-Object @{n='jalon';       e={$_.milestone.title}},
                  @{n='jalon_url';   e={$_.milestone.web_url}},
                  @{n='issue_iid';   e={$_.iid}},
                  @{n='issue_title'; e={$_.title}} |
    Export-Csv -Path "issues.csv" -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Host "$($issues.Count) tickets exportés dans issues.csv"