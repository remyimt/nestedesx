Write-Host "Read the configuration file"
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
$vcenterVmName = "Embedded-vCenter-Server-Appliance"

Write-Host "Connecting to vSphere"
$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
if ($oReturn) {

    try {
        Write-Host "Shutdown Running VM"
        $runningVM = Get-Datacenter -Name "SchoolDatacenter" | Get-VM { $_.Name -ne $vcenterVmName -and $_.PowerState -eq "PoweredOn" }
        $runningVM.foreach{
            Stop-VM -VM $_ -Confirm:$false
        }
        Start-Sleep -Seconds 20
    }
    catch {
        Write-Host "No Running VM"
    }
    Shutdown-VMGuest -VM $vcenterVmName -Confirm:$false
    Start-Sleep -Seconds 60
}
else {
    Write-Host "Connection to vCenter failed !"
}