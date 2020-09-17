# Path to the configuration file
$config_path = $PSScriptRoot + "/configuration.json"
Write-Host ("Config path: {0}" -f $PSScriptRoot)

# Beautiful colors
$global:DefaultColor = "DarkGray"
$global:ErrorColor = "Red"

# Manage wrong certificate errors
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -Confirm:$false | Out-Null

Write-Host "Read the configuration file" -ForegroundColor $DefaultColor
$global:config = Get-Content -Raw -Path $config_path | ConvertFrom-Json
