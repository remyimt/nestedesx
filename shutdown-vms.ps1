Write-Host "Read the configuration file"
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
$vcenterVmName = "Embedded-vCenter-Server-Appliance"
$datacenter = "SchoolDatacenter"

Write-Host "Connecting to vSphere"
$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
if ($oReturn) {
    Write-Host "Shutdown Running VM"
    $runningVM = Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" }
    if ($runningVM.Count - 1 -eq 0) {
        Write-Host "No running virtual machine!"
    }
    else {
        Write-Host ("Stopping {0} virtual machines:" -f ($runningVM.Count - 1))
        foreach ($vm in $runningVM) {
            if ($vm.Name -eq $vcenterVmName) {
                $vcenterHost = $vm.VMHost
            }
            else {
                Stop-VM -VM $vm -Confirm:$false
            }
        }
        Start-Sleep -Seconds 10
    }
    Write-Host "Stopping the physical ESXi"
    $dc = Get-Datacenter -Name $datacenter
    $pEsx = Get-VMHost -Location $dc | Where-Object { $_ -ne $vcenterHost -and $_.PowerState -eq "PoweredOn" }
    $pEsx.foreach{
        Stop-VMHost -VMHost $_ -Force -Confirm:$false
    }
    Write-Host "Shutdown the vCenter"
    Shutdown-VMGuest -VM $vcenterVmName -Confirm:$false
    Start-Sleep -Seconds 30
}
else {
    Write-Host "Connection to vCenter failed !"
}