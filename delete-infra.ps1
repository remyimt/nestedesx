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
Write-Host "Delete vESXi VM:" -ForegroundColor $DefaultColor
$vms = uselessVM
$vms
$vms | Where-Object { $_.PowerState -eq "PoweredOn" } | Stop-VM -Confirm:$false
$vms | Remove-VM -DeletePermanently -Confirm:$false
Write-Host "Waiting for vESXi losing their connection" -ForegroundColor $DefaultColor
foreach ($dc in (Get-Datacenter -Name ($basenameDC + "*"))) {
    foreach ($vmh in (Get-VMHost -Location $dc)) {
        while ($vmh.ConnectionState -ne "NotResponding") {
            Write-Host ("The vESXi {0} is connected. Waiting for the disconnection..." -f $vmh)
            Start-Sleep -Seconds 10
            $vmh = Get-VMHost -Name $vmh.Name
        }
        Write-Host ("Remove vESXi {0} from Inventory" -f $vmh) -ForegroundColor $DefaultColor
        Remove-VMHost -VMHost $vmh -Confirm:$false
    }
}
Write-Host "Remove clusters" -ForegroundColor $DefaultColor
Get-Cluster | Remove-Cluster -Confirm:$false
Write-Host "Remove Student Datacenters" -ForegroundColor $DefaultColor
Get-Datacenter -Name ($basenameDC + "*") | Remove-Datacenter -Confirm:$false
