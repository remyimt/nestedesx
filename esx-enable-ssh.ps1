# Credentials
$IP = "4.4.0.1"
$USER = "root"
$PWD = "esxpassword"

$esx = Connect-VIServer -Server $IP -Protocol https -User $USER -Password $PWD
Get-VMHostService | Where-Object { $_.Key -eq "TSM-SSH" } | Start-VMHostService
