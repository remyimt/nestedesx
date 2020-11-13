# Every error stops the script immediately
$ErrorActionPreference = "Stop"

# The header reads the configuration file ($config variable)
& "$PSScriptRoot/header.ps1"

# Import the function uselessVM
. ./my-functions.ps1

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd

$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
if ($oReturn) {
    Write-Host "Select all student VM:" -ForegroundColor $DefaultColor
    $vms = uselessVM 'vesx'
    $vms
    Write-Host "Remove orphaned VM:" -ForegroundColor $DefaultColor
    $orphaned = $vms | Where {$_.ExtensionData.Summary.Runtime.ConnectionState -eq "orphaned"}
    $orphaned | Remove-VM -Confirm:$false
    $vms = $vms | Where { $orphaned -notcontains $_ }
    Write-Host "Delete Student VM:" -ForegroundColor $DefaultColor
    $vms | Where-Object { $_.PowerState -eq "PoweredOn" } | Stop-VM -Confirm:$false
    $vms | Remove-VM -DeletePermanently -Confirm:$false
}
