Write-Host "Read the configuration file"
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

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

$userIdx = 1
foreach ($dc in (Get-Datacenter -Name ($basenameDC + "*") | Sort-Object -Property Name)) {
    $userName = "VSPHERE.LOCAL\" + $basenameUser + $userIdx
    Write-Host ("Configure the permissions for the user {0}" -f $userName)
    $oReturn = Get-VIAccount -Name $userName
    if (!$oReturn) {
        Write-Error ("User {0} does not exist, please add the user to the vCenter" -f $userName)
        return
    }
    else {
        Write-Host ("Remove existing permissions for {0}" -f $userName)
        Get-VIPermission -Principal $userName | Remove-VIPermission -Confirm:$false
        Write-Host ("Add permissions on the datacenter {0}" -f $dc.Name)
        $oReturn = Get-VIPermission -Entity $dc | Where-Object { $_.Principal -eq $userName }
        if (!$oReturn) {
            New-VIPermission -Entity $dc -Propagate $true -Principal $userName -Role Admin
        }
        foreach ($h  in (Get-VMHost -Location $dc)) {
            Write-Host ("Get VM associated to the host {0}" -f $h)
            $vesxIdx = $h.Name.split(".")[3] - $vConfig.ip_offset
            if ($vesxIdx -lt 10 ) {
                $vesx = Get-VM -Name ($vConfig.basename + "0" + $vesxIdx)
            }
            else {
                $vesx = Get-VM -Name ($vConfig.basename + $vesxIdx)
            }
            $oReturn = Get-VIPermission -Entity $vesx | Where-Object { $_.Principal -eq $userName }
            if (!$oReturn) {
                New-VIPermission -Entity $vesx -Propagate $true -Principal $userName -Role Admin
            }
        }
        $userIdx++
    }
}