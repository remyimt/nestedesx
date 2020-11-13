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
# New Datacenter basename
$basenameDC = $config.architecture.new_dc_basename


Write-Host "Connecting to vSphere" -ForegroundColor $DefaultColor
$oReturn = $false
while (!$oReturn) {
    try {
        $oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
        while (!$oReturn) {
            Write-Host "Connection failed ! New connection after 20 seconds..."
            Start-Sleep -Seconds 20
            $oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
        }
    }
    catch {
        Write-Host "Connection failed ! New connection after 20 seconds..."
        Start-Sleep -Seconds 20
    }
}

Write-Host "Connect all ESXi in maintenance mode:" -ForegroundColor $DefaultColor
Get-VMHost | Where-Object { $_.ConnectionState -eq "Maintenance" } | Set-VMHost -State "Connected"

Write-Host "Remove Student Datacenters" -ForegroundColor $DefaultColor
Get-Datacenter -Name ($basenameDC + "*") | Remove-Datacenter -Confirm:$false

Write-Host "Delete vESXi VM:" -ForegroundColor $DefaultColor
$vms = uselessVM
$vms | Where-Object { $_.PowerState -eq "PoweredOn" } | Stop-VM -Confirm:$false
$vms | Remove-VM -DeletePermanently -Confirm:$false
