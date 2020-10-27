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
    $vms = uselessVM 'vesx'
    Write-Host ("Detecting {0} VM to delete:" -f $vms.Count)
    $vms
    Start-Sleep -Seconds 5
    foreach ($v in $vms) {
        if ($v.PowerState -eq "PoweredOn") {
            Write-Host "Stopping the VM $v"
            Stop-VM -VM $v -Confirm:$false
        }
    }
    Write-Host "Delete the following VM:"
    $vms
    Start-Sleep -Seconds 5
    foreach ($v in $vms) {
        Remove-VM -VM $v -Confirm:$false
    }
}
