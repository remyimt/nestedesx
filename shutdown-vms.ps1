# The header reads the configuration file ($config variable)
& "$PSScriptRoot/header.ps1"

# Import the function uselessVM
. ./my-functions.ps1

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
$vcenterHost = $config.vcenter.host

$datacenter = "SchoolDatacenter"
$esxName = $args[0]

if ( $esxName.count -eq 0 ) {
    Write-Host "Shutdown VM on ESXi" -ForegroundColor $DefaultColor
    Write-Host "Usage: ./shutdown-vms.ps1 esx_ip" -ForegroundColor $DefaultColor
    exit 13
}
Write-Host "Connecting to vSphere" -ForegroundColor $DefaultColor
$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
if ($oReturn) {
    Write-Host "Shutdown Running VM" -ForegroundColor $DefaultColor
    $runningVM = uselessVM | Where-Object { $_.PowerState -eq "PoweredOn" }
    if ( $runningVM.Count -gt 0 ) {
        $runningVM | Stop-VM -Confirm:$false
    }
    else {
        Write-Host "No running VM!" -ForegroundColor $ErrorColor
    }
}
else {
    Write-Host "Connection to vCenter failed !" -ForegroundColor $ErrorColor
}
