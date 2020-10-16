# The header reads the configuration file ($config variable)
& "$PSScriptRoot/header.ps1"

# Import the function NameFromMAC
. ./my-functions.ps1

# Every error stops the script immediately
$ErrorActionPreference = "Stop"

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
# New Datacenter basename
$basenameDC = $config.architecture.new_dc_basename
# vESXi configuration : root account and password
$vConfig = $config.virtual_esx
# New user basename
$basenameUser = $config.architecture.user_basename

# Connection to vSphere
Write-Host "+ Connecting to vSphere"
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

# Check that required users exist
$userIdx = 1
$missingUsers = @()
foreach ($dc in Get-Datacenter -Name ($basenameDC + "*")) {
    $userName = "VSPHERE.LOCAL\" + $basenameUser + $userIdx++
    $oReturn = Get-VIAccount -Name $userName
    if (!$oReturn) {
        $missingUsers += $userName
    }
}
if ($missingUsers.Count -gt 0) {
    Write-Host "Please create the following users before executing again this script:"
    $missingUsers
    return
}

# Add permissions to users
$userIdx = 1
foreach ($dc in (Get-Datacenter -Name ($basenameDC + "*") | Sort-Object -Property Name)) {
    $userName = "VSPHERE.LOCAL\" + $basenameUser + $userIdx
    Write-Host ("+ Configure the permissions for the user {0}" -f $userName)
    $oReturn = Get-VIAccount -Name $userName
    if (!$oReturn) {
        Write-Error ("User {0} does not exist, please add the user to the vCenter" -f $userName)
        return
    }
    else {
        Write-Host ("Remove existing permissions for {0}" -f $userName)
        Get-VIPermission -Principal $userName | Remove-VIPermission -Confirm:$false
        Write-Host ("Add permissions to the datacenter {0}" -f $dc.Name)
        $oReturn = Get-VIPermission -Entity $dc | Where-Object { $_.Principal -eq $userName }
        if (!$oReturn) {
            New-VIPermission -Entity $dc -Propagate $true -Principal $userName -Role Admin | Out-Null
        }
        foreach ($h  in (Get-VMHost -Location $dc)) {
            Write-Host ("Get VM associated to the host {0}" -f $h)
            $mac = $h | Get-VMHostNetworkAdapter | Select-Object -Property Mac
            $vmName = NameFromMAC($mac[0].Mac)
            $vesx = Get-VM -Name $vmName
            Write-Host ("Add permissions to the VM {0}" -f $vesx)
            $oReturn = Get-VIPermission -Entity $vesx | Where-Object { $_.Principal -eq $userName }
            if (!$oReturn) {
                New-VIPermission -Entity $vesx -Propagate $true -Principal $userName -Role Admin | Out-Null
            }
        }
        $userIdx++
    }
}
