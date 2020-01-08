# Every error stops the script immediately
$ErrorActionPreference = "Stop"
# Beautiful colors
$DefaultColor = "DarkGray"
$ErrorColor = "Red"

#### Functions
function Wait-Hosts {
    foreach ($vmh in (Get-VMHost | Where-Object { $_.ConnectionState -ne "Connected" })) {
        while ($vmh.ConnectionState -ne "Connected") {
            Write-Host ("Waiting the host {0} (State: {1})" -f $vmh, $vmh.ConnectionState)
            Start-Sleep -Seconds 20
            $vmh = Get-VMHost $vmh.Name
        }
    }
}

# Copy this function to the file set-permissions.ps1
function NameFromMAC {
    param (
        [string]
        $macAddr
    )
    $array = $macAddr.Split(":")
    return $vConfig.basename + $array[4] + "_" + $array[5]
}
function NameFromIP {
    param (
        [string]
        $ipAddr
    )
    $array = $ipAddr.Split(".")
    return "vDatastore" + $array[2] + "_" + $array[3]
}
function Get-VMFromHost {
    param (
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]
        $esx
    )
    # Retrieve the MAC address of the host to compute the VM name
    $mac = $esx | Get-VMHostNetworkAdapter | Select-Object -Property Mac
    $vmName = NameFromMAC($mac[0].Mac)
    return Get-VM -Name $vmName
}

function Remove-HostFromDC {
    param (
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]
        $esx
    )
    # Disable the vSan to remove the vSan datastore
    $cl = Get-Cluster -VMHost $esx | Where-Object { $_.VsanEnabled }
    if ($cl) {
        Write-Host ("Disable vSan for the cluster {0}" -f $cl) -ForegroundColor $DefaultColor
        Set-Cluster -Cluster $cl -VsanEnabled:$false -Confirm:$false
        # Wait the end of the vSan configuration
        Start-Sleep -Seconds 2
    }
    # Get the associated VM
    $vm = Get-VMFromHost($esx)
    # Delete the host and poweroff the VM
    Write-Host ("Remove the vESXi {0} from the inventory" -f $esx) -ForegroundColor $DefaultColor
    Set-VMHost -VMHost $esx -State "Maintenance" -Confirm:$false | Out-Null
    Remove-VMHost -VMHost $esx -Confirm:$false | Out-Null
    Write-Host ("Power off the VM associated to the host {0}" -f $esx) -ForegroundColor $DefaultColor
    $vm | Stop-VM -Confirm:$false | Out-Null
}
#### End of Functions

Write-Host "Read the configuration file" -ForegroundColor $DefaultColor
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
# ESXi configuration : IP, root account and password
$esxConfig = $config.physical_esx
# vESXi configuration : root account and password
$vConfig = $config.virtual_esx
# List of VM host objects
$ip2obj = @{ }
# ESXi Cluster Name
$datacenter = $config.architecture.main_dc
# Path to the OVF file to deploy
$vEsxOVF = $config.architecture.ovf
# Number of vESXi per datacenter
$nbEsxPerDC = $config.architecture.nb_vesx_datacenter
# New Datacenter basename
$basenameDC = $config.architecture.new_dc_basename
# ISO files to upload on vESXi datastores
$isoPrefix = $config.architecture.iso_prefix
$iso = $config.architecture.iso

# Enable/disable the vSan Configuration
try {
    $vSanMode = [System.Convert]::ToBoolean($config.architecture.vsan)
}
catch [FormatException] {
    $vSanMode = $false
}
# Add a default datastore to ESXi without datastore (true/false)
try {
    $alwaysDatastore = [System.Convert]::ToBoolean($config.architecture.always_datastore)
}
catch [FormatException] {
    $alwaysDatastore = $false
}

$totalVesx = 0
# Check the vESXi information from the configuration file
if ($vSanMode) {
    if ($nbEsxPerDC -lt 3) {
        Write-Host("The minimum number of ESXi in vSan clusters is 3. Please, disable the vSan mode or increase the number of vESX per datacenter (nb_vesx_datacenter)") -ForegroundColor $ErrorColor
        return
    }
}
foreach ($e in $esxConfig) {
    if ($e.nb_vesx -gt $e.dhcp_max_addr) {
        Write-Host ("The number of vESXi ({0}) of the pESXi {1} can not be greater than the number of DHCP addresses ({2}).
        Please check your configuration file." -f $e.nb_vesx, $e.ip, $e.dhcp_max_addr) -ForegroundColor $ErrorColor
        return
    }
    $totalVesx += $e.nb_vesx
}
if ($totalVesx % $nbEsxPerDC -ne 0) {
    Write-Host ("The vESXi can not be fairly distributed on datacenters. Total vESXi : {0}" -f $totalVesx) -ForegroundColor $ErrorColor
    return
}
$totalDc = $totalVesx / $nbEsxPerDC

# Connection to vSphere
Write-Host "Connecting to vSphere" -ForegroundColor $DefaultColor
$oReturn = $false
while (!$oReturn) {
    try {
        $oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
        while (!$oReturn) {
            Write-Host "Connection failed ! New connection after 20 seconds..." -ForegroundColor $DefaultColor
            Start-Sleep -Seconds 20
            $oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
        }
    }
    catch {
        Write-Host "Connection failed ! New connection after 20 seconds..." -ForegroundColor $DefaultColor
        Start-Sleep -Seconds 20
    }
}

# Add ESXi to the main datacenter
Write-Host "Configure the physical ESXi" -ForegroundColor $DefaultColor
$missing = @()
foreach ($e in $esxConfig) {
    $oReturn = Test-Connection -computername $e.ip -Count 1 -quiet
    if (!$oReturn) {
        $missing += $e
    }
    # Wait to avoid overfilling the network
    Start-Sleep -Milliseconds 300
}
if ($missing.Count -gt 0) {
    Write-Host $missing.Count "ESXi are missing:" -ForegroundColor $ErrorColor
    $missing.foreach{
        Write-Host $_.ip -ForegroundColor $ErrorColor
    }
    return
}
Write-Host "Retrieve the datacenter $datacenter" -ForegroundColor $DefaultColor
try {
    $dc = Get-Datacenter -Name $datacenter
}
catch {
    Write-Host "Creating the datacenter" -ForegroundColor $DefaultColor
    $folder = Get-Folder -NoRecursion
    $dc = New-Datacenter -Location $folder -Name $datacenter
    Start-Sleep -Seconds 5
}
foreach ($e in $esxConfig) {
    try {
        $ip2obj[$e.ip] = Get-VMHost -Name $e.ip
    }
    catch {
        Write-Host ("Add the host {0} to $datacenter" -f $e.ip) -ForegroundColor $DefaultColor
        $ip2obj[$e.ip] = Add-VMHost -Name $e.ip -Location $datacenter -User $e.user -Password $e.pwd -Force
    }
}
# Waiting for ESXi connection
foreach ($e in $esxConfig) {
    $vmh = $ip2obj[$e.ip]
    while ($vmh.ConnectionState -ne "Connected") {
        Write-Host ("The vESXi {0} is not connected. Waiting..." -f $vmh) -ForegroundColor $DefaultColor
        Start-Sleep -Seconds 10
        $vmh = Get-VMHost -Name $vmh.Name
    }
}

# Delete ESXi VM with issues (i.e., vESXi hosts with a vSanDatastore that does not belong to a vSan cluster)
Write-Host "Delete vESXi with configuration issues" -ForegroundColor $DefaultColor
# Get the datastores that do not belong to a vSan cluster
$dsWithIssues = Get-Datastore -Name "vsan*" | Where-Object { (Get-Cluster -Name "vsan*" | Get-Datastore) -CNotContains $_ }
$dsWithIssues
if ($dsWithIssues.Count -gt 0) {
    # Disconnect the hosts using these datastores from their datacenter
    foreach ($vmh in (Get-VMHost -Datastore $dsWithIssues)) {
        $vm = Get-VMFromHost($vmh)
        Write-Host("Configuration issue detected: Remove the host {0} and delete the VM {1}" -f $vmh, $vm) -ForegroundColor $DefaultColor
        $vmh | Remove-VMHost -Confirm:$false
        # Delete associated VM
        $vm | Stop-VM -Confirm:$false | Remove-VM -DeletePermanently -Confirm:$false | Out-Null
    }
}
# Power off ESXi VM (vESXi)
Write-Host "Power off the useless vESXi" -ForegroundColor $DefaultColor
foreach ($e in $esxConfig) {
    $onVesx = Get-VM -Name "vesx*" -Location $ip2obj[$e.ip] | Where-Object { $_.PowerState -eq "PoweredOn" } | Sort-Object -Property "Name" -Descending
    for ($i = 0; $i -lt ($onVesx.Count - $e.nb_vesx); $i++) {
        # Remove the vESXi from the datacenter
        Write-Host ("Disconnect the vESXi associated to {0}" -f $onVesx[$i]) -ForegroundColor $DefaultColor
        $esxName = $onVesx[$i].Guest.IPAddress[0]
        try {
            $vmh = Get-VMHost -Name $esxName
            Remove-HostFromDC($vmh)
        }
        catch {
            Write-Host("Not found host {0}" -f $esxName) -ForegroundColor $ErrorColor
            Write-Host("Stop the VM {0}" -f $onVesx[$i])
            $onVesx[$i] | Stop-VM -Confirm:$false
        }
    }
}

Write-Host "Delete unnecessary datacenters" -ForegroundColor $DefaultColor
# Remove empty datacenters
Get-Datacenter | Where-Object { (Get-VMHost -Location $_).Count -eq 0 } | Remove-Datacenter -Confirm:$false
# Get the datacenters and compute the number of connected vESXi
$dcs = Get-Datacenter -Name ($basenameDC + "*") | Select-Object Name, @{N = "Hosts#"; E = { @(Get-VMHost -Location $_ ).Count } } | Sort-Object -Property "Hosts#"
# Remove unnecessary datacenters
if ($dcs.Count -gt $totalDc) {
    # Too many datacenters exist
    foreach ($dc in ($dcs | Select-Object -First ($dcs.Count - $totalDc))) {
        Write-Host ("Delete the datacenter {0}" -f $dc) -ForegroundColor $DefaultColor
        foreach ($esx in (Get-VMHost -Location $dc.Name)) {
            Remove-HostFromDC($esx)
        }
        Remove-Datacenter $dc.Name -Confirm:$false | Out-Null
    }
}

# Check the number of vESXi on every datacenter
Write-Host "Remove hosts on overload datacenters" -ForegroundColor $DefaultColor
$dcs = Get-Datacenter -Name ($basenameDC + "*")
foreach ($dc in $dcs) {
    $hosts = Get-VMHost -Location $dc | Sort-Object -Descending
    for ($i = 0; $i -lt ($hosts.Count - $nbEsxPerDC); $i++) {
        Remove-HostFromDC($hosts[$i])
    }
}

# Disable maintenance mode on vESXi
Get-VMHost | Where-Object { $_.ConnectionState -eq "Maintenance" } | Set-VMHost -State "Connected"

# Create ESXi VM (vESXi) in the infrastructure
foreach ($e in $esxConfig) {
    $onVesx = Get-VM -Name "vesx*" -Location $ip2obj[$e.ip] | Where-Object { $_.PowerState -eq "PoweredOn" }
    $offVesx = Get-VM -Name "vesx*" -Location $ip2obj[$e.ip] | Where-Object { $_.PowerState -eq "PoweredOff" } | Sort-Object
    Write-Host ("Number of vESXi hosted on {0}: {1} / {2}" -f $e.ip, $onVesx.Count, $e.nb_vesx) -ForegroundColor $DefaultColor
    if ($e.nb_vesx -gt $onVesx.Count -and $offVesx.Count -gt 0) {
        # There are missing vESXi, start existing VM
        Write-Host ("Start vESXi on {0}" -f $e.ip) -ForegroundColor $DefaultColor
        $offVesx | Select-Object -First $e.nb_vesx | Start-VM -Confirm:$false | Out-Null
    }
    $onVesx = Get-VM -Name "vesx*" -Location $ip2obj[$e.ip] | Where-Object { $_.PowerState -eq "PoweredOn" }
    # Collect information about existing vESXi
    $existingMacs = @()
    foreach ($mac in $onVesx | Get-NetworkAdapter | Select-Object -Property MacAddress) {
        $existingMacs += $mac
    }
    $macIdx = 1
    for ($i = $onVesx.Count; $i -lt $e.nb_vesx; $i++) {
        # Compute the mac address for the new vESXi
        do {
            if ($macIdx -lt 10) {
                $idxStr = "0" + $macIdx
            }
            else {
                $idxStr = $macIdx
            }
            $macStr = $e.dhcp_mac_addr + $idxStr
            $macIdx++
        } while ($existingMacs -match $macStr)
        $nameStr = NameFromMAC($macStr)
        Write-Host ("Creating the virtualized ESXi {0}" -f $nameStr ) -ForegroundColor $DefaultColor
        if ($createFromClone) {
            # Create the vESXi from an existing vESXi
            $vesx = New-VM -VM $cloneSrc -VMHost $ip2obj[$e.ip] -Name $nameStr -DiskStorageFormat Thin
        }
        else {
            # Create the vESXi from OVF
            $vesx = Import-vApp -Source $vEsxOVF -VMHost $ip2obj[$e.ip] -Name $nameStr -DiskStorageFormat Thin
            $createFromClone = $true
            $cloneSrc = $vesx
        }
        # Set the MAC address
        $vesx | Get-NetworkAdapter | Set-NetworkAdapter -MacAddress $macStr -Confirm:$false -StartConnected:$true | Out-Null
        # Power on the vESXi
        Write-Host ("Power on the VM " + $nameStr) -ForegroundColor $DefaultColor
        $vesx | Start-VM | Out-Null
        Start-Sleep -Seconds 1
        $existingMacs += $macStr
    }
    $onVesx = Get-VM -Name "vesx*" -Location $ip2obj[$e.ip] | Where-Object { $_.PowerState -eq "PoweredOn" }
    Write-Host ("Number of vESXi hosted on {0}: {1} / {2}" -f $e.ip, $onVesx.Count, $e.nb_vesx) -ForegroundColor $DefaultColor
}

$onVesx = Get-VM -Name "vesx*" | Where-Object { $_.PowerState -eq "PoweredOn" }
Write-Host ("Check connection of {0} vESXi" -f $onVesx.Count) -ForegroundColor $DefaultColor
$vesxIPs = @()
foreach ($vesx in $onVesx) {
    $vesxIp = $vesx.Guest.IPAddress[0]
    while (!$vesxIp) {
        Write-Host ("Waiting the IP configuration of {0}" -f $vesx) -ForegroundColor $DefaultColor
        Start-Sleep 10
        $vesx = Get-VM -Name $vesx.Name
        $vesxIp = $vesx.Guest.IPAddress[0]
    }
    $oReturn = Test-Connection -computername $vesxIp -Count 1 -quiet
    while (!$oReturn) {
        Start-Sleep -Seconds 20
        $oReturn = Test-Connection -computername $vesxIp -Count 1 -quiet
    }
    try {
        Get-VMHost -Name $vesxIp | Out-Null
    }
    catch {
        $vesxIPs += $vesxIp
    }
    # Wait to avoid overfilling the network
    Start-Sleep -Milliseconds 300
}
Write-Host ("Available vESXi: ") -ForegroundColor $DefaultColor
$vesxIPs

Wait-Hosts

# Compute available names for datacenter creations
Write-Host "Connect the vESXi to datacenters" -ForegroundColor $DefaultColor
$dcs = Get-Datacenter -Name ($basenameDC + "*")
$newDC = @()
if ($dcs.Count -lt $totalDc) {
    Write-Host "Create new datacenters" -ForegroundColor $DefaultColor
    for ($i = 1; ($newDC.Count + $dcs.Count) -lt $totalDc; $i++) {
        $dcName = $basenameDC + $i
        try {
            Get-Datacenter -Name $dcName | Out-Null
            Write-Host ("Datacenter {0} already exists" -f $dcName) -ForegroundColor $DefaultColor
        }
        catch {
            Write-Host ("Create a new datacenter {0}" -f $dcName) -ForegroundColor $DefaultColor
            $folder = Get-Folder -NoRecursion
            $newDC += New-Datacenter -Location $folder -Name $dcName
        }
    }
}

Wait-Hosts

# Assign vESXi to datacenters
$availableIdx = 0
foreach ($dc in Get-Datacenter -Name ($basenameDC + "*")) {
    Write-Host ("Configure the datacenter {0}" -f $dc) -ForegroundColor $DefaultColor
    $vesx = Get-VMHost -Location $dc
    for ($i = $vesx.Count; $i -lt $nbEsxPerDC; $i++, $availableIdx++) {
        # Connect vESXi to the datacenter
        Write-Host ("Connect {0} to the {1}" -f $vesxIPs[$availableIdx], $dc) -ForegroundColor $DefaultColor
        $vmh = Add-VMHost -Name $vesxIPs[$availableIdx] -Location $dc -User $vConfig.user -Password $vConfig.pwd -Force
        # Check the datastore configuration
        $ds = Get-Datastore -VMHost $vmh | Where-Object { $_.Name -notlike "vSan*" }
        $dsName = NameFromIP($vesxIPs[$availableIdx])
        if ($ds.Count -gt 0 -and $ds[0].Name -ne $dsName) {
            # Update the datastore ID to an unique ID
            Write-Host ("Removing the datastore of {0}" -f $vmh) -ForegroundColor $DefaultColor
            Remove-Datastore -VMHost $vmh -Datastore $ds[0] -Confirm:$false | Out-Null
            Write-Host ("Creating a new datastore for {0}" -f $vmh) -ForegroundColor $DefaultColor
            New-Datastore -VMHost $vmh -Name $dsName -Path mpx.vmhba0:C0:T0:L0 -Vmfs -Confirm:$false | Out-Null
        }
    }
}

# Create local datastore for vESXi
if ($alwaysDatastore) {
    foreach ($dc in Get-Datacenter -Name ($basenameDC + "*")) {
        Write-Host ("Configure datastores for hosts on {0}" -f $dc) -ForegroundColor $DefaultColor
        $vmh = Get-VMHost -Location $dc
        foreach ($esx in $vmh) {
            Write-Host ("Configuring the datastore of {0}" -f $esx) -ForegroundColor $DefaultColor
            $ds = Get-Datastore -VMHost $esx
            if ($ds.Count -eq 0) {
                # Create a datastore from the smallest disk
                $disks = Get-VMHostDisk -VMHost $esx | Sort-Object -Property TotalSectors
                $dsName = NameFromIP($esx.Name)
                New-Datastore -VMHost $esx -Name $dsName -Path $disks[0].ScsiLun -Vmfs -Confirm:$false | Out-Null
            }
        }
    }
}
# Enable Promiscuous mode to allow VM on nested ESXi to communicate
Write-Host "Allow the promiscuous mode on virtual switches" -F $DefaultColor
Get-VirtualSwitch -Standard | Where-Object { !(Get-SecurityPolicy -VirtualSwitch $_).AllowPromiscuous } | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true | Out-Null

# Create vSan Clusters
if ($vSanMode) {
    $dcs = Get-Datacenter -Name ($basenameDC + "*")
    Write-Host "Creating vSan clusters" -ForegroundColor $DefaultColor
    foreach ($d in $dcs) {
        Write-Host ("Creating the cluster {0}" -f ("vSan" + $d.Name)) -ForegroundColor $DefaultColor
        try {
            $cl = Get-Cluster -Name ("vSan" + $d.Name)
            Write-Host("Cluster {0} already exists!" -f $cl) -ForegroundColor $DefaultColor
        }
        catch {
            $cl = New-Cluster -Name ("vSan" + $d.Name) -Location $d
        }
        Write-Host ("Configuring vESXi to create the vSan storage from the cluster {0}" -f $cl) -ForegroundColor $DefaultColor
        foreach ($vmh in (Get-VMHost -Location $d)) {
            Write-Host ("Configuring the vESXi {0}" -f $vmh) -ForegroundColor $DefaultColor
            Move-VMHost -VMHost $vmh -Destination $cl | Out-Null
            $na = Get-VMHostNetworkAdapter -VMHost $vmh -VMKernel | Where-Object { ! $_.VsanTrafficEnabled }
            if ($na.Count -gt 0) {
                Write-Host "Enable vSan system" -ForegroundColor $DefaultColor
                $na | Set-VMHostNetworkAdapter -VsanTrafficEnabled $true -Confirm:$false | Out-Null
                $dataDisk = $vmh | Get-VMHostDisk | Where-Object { $_.TotalSectors -eq 83886080 }
                Write-Host "Configuring disks" -ForegroundColor $DefaultColor
                $cacheDisk = $vmh | Get-VMHostDisk | Where-Object { $_.TotalSectors -eq 20971520 }
                if (!$cacheDisk.ScsiLun.IsSsd) {
                    Write-Host ("Mark the disk {0} as a SSD Disk" -f $cacheDisk) -ForegroundColor $DefaultColor
                    $cli = Get-EsxCli -VMHost $vmh
                    $sat = ($cli.storage.nmp.device.list() | Where-Object { $_.Device -eq $cacheDisk.ScsiLun.CanonicalName }).StorageArrayType
                    $cli.storage.nmp.satp.rule.add($null, $null, $null, $cacheDisk.ScsiLun.CanonicalName, $null, $null, $null, "enable_ssd", $null, $null, $sat, $null, $null, $null) | Out-Null
                    $cli.storage.core.claiming.reclaim($cacheDisk.ScsiLun.CanonicalName) | Out-Null
                }
                # Use RunAsync to run this task in order to avoid weird error (bug ?)
                $partitions = $dataDisk | Get-VMHostDiskPartition
                if ($partitions.Count -eq 0) {
                    $task = New-VsanDiskGroup -VMHost $vmh -DataDiskCanonicalName $dataDisk -SsdCanonicalName $cacheDisk -RunAsync
                    while ($task.state -eq "Running") {
                        Start-Sleep -Seconds 10
                        $task = Get-Task -ID $task.id
                    }
                }
            }
        }
        if (!$cl.VsanEnabled) {
            Write-Host ("Configuring the vSan for the cluster {0}" -f ("vSan" + $d.Name)) -ForegroundColor $DefaultColor
            Set-Cluster -Cluster $cl -VsanEnabled:$true -Confirm:$false | Out-Null
            # Get the number at the end of the cluster name
            $cl.Name -match "(\d+)$" | Out-Null
            $dsName = "vsanDatastore" + $Matches[1]
            # Rename the datastore
            if ($cl.Name -ne $dsName) {
                $cl | Get-Datastore -Name "vsan*" | Set-Datastore -Name $dsName | Out-Null
            }
        }
    }
}
else {
    # Disable vSan clusters
    Write-Host "Disable vSan mode on clusters" -ForegroundColor $DefaultColor
    Get-Cluster | Where-Object { $_.VsanEnabled } | Set-Cluster -VsanEnabled:$false -Confirm:$false
}

# Copy ISO files on datastores
$ds = Get-Datastore -Name "vDatastore*"
if ($iso.Count -gt 0 -and $ds.Count -gt 0) {
    Write-Host ("Copy files on vESXi datastores: {0}" -f $iso) -ForegroundColor $DefaultColor
    # DatastoreId = full_path - Use the full path to mount the ISO file
    $id2path = @{ }
    $firstSt, $otherSt = $ds
    foreach ($isoFile in $iso) {
        Write-Host ("Looking for {0} on datastore {1}" -f $isoFile, $firstSt.Name) -ForegroundColor $DefaultColor
        $myFile = Get-ChildItem -Path $firstSt.DatastoreBrowserPath | Where-Object { $_.Name -like $isoFile }
        if ($myFile.Count -eq 0) {
            Write-Host "Upload the file on" $firstSt.Name -ForegroundColor $DefaultColor
            Copy-DatastoreItem -Item ($isoPrefix + $isoFile) -Destination $firstSt.DatastoreBrowserPath
            # Get the file for later copy
            $myFile = Get-ChildItem -Path $firstSt.DatastoreBrowserPath | Where-Object { $_.Name -like $isoFile }
        }
        else {
            Write-Host ("{0} exists on {1}" -f $isoFile, $firstSt.Name) -ForegroundColor $DefaultColor
        }
        $copyFile = $myFile[0]
        $id2path[$copyFile.DatastoreId] = $copyFile.DatastoreFullPath

        foreach ($o in $otherSt) {
            Write-Host ("Looking for {0} on datastore {1}" -f $isoFile, $o.Name) -ForegroundColor $DefaultColor
            $myFile = Get-ChildItem -Path $o.DatastoreBrowserPath | Where-Object { $_.Name -like $isoFile }
            if ($myFile.Count -eq 0) {
                Write-Host ("Upload the file on {0} from {1}" -f $o.Name, $firstSt.Name) -ForegroundColor $DefaultColor
                Copy-DatastoreItem -Item $copyFile -Destination $o.DatastoreBrowserPath
                $myFile = Get-ChildItem -Path $o.DatastoreBrowserPath | Where-Object { $_.Name -like $isoFile }
            }
            else {
                Write-Host ("{0} exists on {1}" -f $isoFile, $o.Name) -ForegroundColor $DefaultColor
            }
            $id2path[$myFile[0].DatastoreId] = $myFile[0].DatastoreFullPath
        }
    }
}

# Disable maintenance mode on vESXi (sometimes, vESXi stay in maintenance mode)
Get-VMHost | Where-Object { $_.ConnectionState -eq "Maintenance" } | Set-VMHost -State "Connected"
