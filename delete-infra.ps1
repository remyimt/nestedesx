# Every error stops the script immediately
$ErrorActionPreference = "Stop"
Write-Host "Read the configuration file"
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
# New Datacenter basename
$basenameDC = $config.architecture.new_dc_basename


Write-Host "Connecting to vSphere"
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
Write-Host "Delete Student VM:"
$vms = Get-VM | Where-Object { $_.Name -notlike "vesx*" -and $_.Name -notlike "Embedded*" -and (Get-VMHost -VM $_).ConnectionState -eq "Connected" }
$vms | Where-Object { $_.PowerState -eq "PoweredOn" } | Stop-VM -Confirm:$false
$vms | Remove-VM -DeletePermanently -Confirm:$false
Write-Host "Delete vESXi VM:"
$vms = Get-VM | Where-Object { $_.Name -like "vesx*" -and $_.Name -notlike "Embedded*" }
$vms | Where-Object { $_.PowerState -eq "PoweredOn" } | Stop-VM -Confirm:$false
$vms | Remove-VM -DeletePermanently -Confirm:$false
Write-Host "Waiting for vESXi losing their connection"
foreach ($dc in (Get-Datacenter -Name ($basenameDC + "*"))) {
    foreach ($vmh in (Get-VMHost -Location $dc)) {
        while ($vmh.ConnectionState -ne "NotResponding") {
            Write-Host ("The vESXi {0} is connected. Waiting for the deconnection..." -f $vmh)
            Start-Sleep -Seconds 10
            $vmh = Get-VMHost -Name $vmh.Name
        }
        Write-Host ("Remove vESXi {0} from Inventory" -f $vmh)
        Remove-VMHost -VMHost $vmh -Confirm:$false
    }
}
Write-Host "Remove clusters"
Get-Cluster | Remove-Cluster -Confirm:$false
Write-Host "Remove Student Datacenters"
Get-Datacenter -Name ($basenameDC + "*") | Remove-Datacenter -Confirm:$false