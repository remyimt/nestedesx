# Every error stops the script immediately
$ErrorActionPreference = "Stop"

Write-Host "Read the configuration file"
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd

$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
if ($oReturn) {
    $vms = Get-VM | Where-Object { $_.Name -notlike "vesx*" -and $_.Name -notlike "Embedded*" }
    Write-Host ("Detecting {0} VM to delete:" -f $vms.Count)
    foreach ($v in $vms) {
        if ($v.PowerState -eq "PoweredOn") {
            Write-Host "Stopping the VM $v"
            Stop-VM -VM $v -Confirm:$false
            Start-Sleep -Seconds 10
        }
        Remove-VM -VM $v -Confirm:$false
    }
}