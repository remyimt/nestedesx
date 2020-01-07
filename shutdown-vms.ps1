Write-Host "Read the configuration file"
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
$vcenterHost = $config.vcenter.host

$datacenter = "SchoolDatacenter"

Write-Host "Connecting to vSphere"
$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
if ($oReturn) {
    Write-Host "Shutdown Running VM"
    $runningVM = Get-VM | Where-Object { $_.Name -notlike "vesx*" -and $_.Name -notlike "Embedded*" -and $_.PowerState -eq "PoweredOn" }
    if ($runningVM.Count -lt 0) {
        $runningVM | Stop-VM -Confirm:$false
        Start-Sleep -Seconds 10
    }
    else {
        Write-Host "No running VM!"
    }
    Write-Host "Shutdown Running vESXi"
    $runningVM = Get-VM -Name "vesx*" | Where-Object { $_.PowerState -eq "PoweredOn" }
    if ($runningVM.Count -eq 0) {
        Write-Host "No running vEsxi!"
    }
    else {
        Write-Host ("Stopping {0} virtual machines:" -f ($runningVM.Count - 1))
        foreach ($vm in $runningVM) {
            Stop-VM -VM $vm -Confirm:$false
        }
        Start-Sleep -Seconds 10
    }
    Write-Host "Stopping the physical ESXi"
    $dc = Get-Datacenter -Name $datacenter
    $pEsx = Get-VMHost -Location $dc | Where-Object { $_.Name -ne $vcenterHost -and $_.PowerState -eq "PoweredOn" }
    if ($pEsx.Count -eq 0) {
        Write-Host "No running physical ESXi"
    }
    else {
        $pEsx.foreach{
            Write-Host("Stop the host {0]" -f $_)
            Stop-VMHost -VMHost $_ -Force -Confirm:$false
        }
    }
}
else {
    Write-Host "Connection to vCenter failed !"
}