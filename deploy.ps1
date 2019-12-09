# Every error stops the script immediately
$ErrorActionPreference = "Stop"
# Beautiful colors
$DefaultColor = "DarkGray"
$ErrorColor = "Red"

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
# Add a default datastore to ESXi without datastore
try {
    $alwaysDatastore = [System.Convert]::ToBoolean($config.architecture.always_datastore) 
}
catch [FormatException] {
    $alwaysDatastore = $false
}

$totalVesx = 0
# Check the number of vESX to create
foreach ($e in $esxConfig) {
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

# Power off ESXi VM (vESXi)
Write-Host "Power off the useless vESXi" -ForegroundColor $DefaultColor
foreach ($e in $esxConfig) {
    $onVesx = Get-VM -Name "vesx*" -Location $ip2obj[$e.ip] | Where-Object { $_.PowerState -eq "PoweredOn" } | Sort-Object -Property "Name" -Descending
    for ($i = 0; $i -lt ($onVesx.Count - $e.nb_vesx); $i++) {
        # Remove the vESXi from the datacenter
        Write-Host ("Disconnect the vESXi associated to {0}" -f $onVesx[$i]) -ForegroundColor $DefaultColor
        $esxName = $onVesx[$i].Guest.IPAddress[0]
        $esx = Get-VMHost -Name $esxName
        $cl = Get-Cluster -VMHost $esx | Where-Object { $_.VsanEnabled }
        if ($cl) {
            Write-Host ("Disable vSan for the cluster {0}" -f $cl) -ForegroundColor $DefaultColor
            Set-Cluster -Cluster $cl -VsanEnabled:$false -Confirm:$false
        }
        Write-Host ("Remove the vESXi {0} from the inventory" -f $esx) -ForegroundColor $DefaultColor
        Set-VMHost -VMHost $esx -State "Maintenance" -Confirm:$false
        Remove-VMHost -VMHost $esx -Confirm:$false
        # Power off the VM
        if ($onVesx.PowerState -eq "PoweredOn") {
            Stop-VM -VM $onVesx[$i] -Confirm:$false | Out-Null
        }
    }
}
Write-Host "Delete unnecessary datacenters" -ForegroundColor $DefaultColor
Get-Datacenter | Where-Object { (Get-VMHost -Location $_).Count -eq 0 } | Remove-Datacenter -Confirm:$false
# Get the datacenters and compute the number of connected vESXi
$dcs = Get-Datacenter -Name ($basenameDC + "*") | Select-Object Name, @{N = "Hosts#"; E = { @(Get-VMHost -Location $_ ).Count } } | Sort-Object -Property "Hosts#"
if ($dcs.Count -gt $totalDc) {
    # Too many datacenters exist
    foreach ($dc in ($dcs | Select-Object -First ($dcs.Count - $totalDc))) {
        Write-Host ("Delete the datacenter {0}" -f $dc) -ForegroundColor $DefaultColor
        foreach ($esx in (Get-VMHost -Location $dc.Name)) {
            Write-Host ("Remove the vESXi {0} from the inventory" -f $esx) -ForegroundColor $DefaultColor
            Set-VMHost -VMHost $esx -State "Maintenance" -Confirm:$false
            Remove-VMHost -VMHost $esx -Confirm:$false
            # Power off the VM
            if ($onVesx.PowerState -eq "PoweredOn") {
                Stop-VM -VM $onVesx[$i] -Confirm:$false | Out-Null
            }
        }
        Remove-Datacenter $dc.Name -Confirm:$false | Out-Null
    }
}

# Disable maintenance mode on vESXi
Get-VMHost | Where-Object { $_.ConnectionState -eq "Maintenance" } | Set-VMHost -State "Connected"

# Compute available names and MAC addresses for vESXi creations
$availableInfo = @()
if ((Get-VM -Name "vesx*" | Where-Object { $_.PowerState -eq "PoweredOn" }).Count -lt $totalVesx) {
    for ($i = 1; $i -le $vConfig.dhcp_max_ip; $i++) {
        if ($i -lt 10) {
            $NewEsxName = $vConfig.basename + "0" + $i
            $macAddr = "00:50:56:a1:00:0" + $i
        }
        else {
            $NewEsxName = $vConfig.basename + $i
            $macAddr = "00:50:56:a1:00:" + $i
        }
        try {
            $vesx = Get-VM -Name $NewEsxName
            Write-Host ("Check the configuration of {0}" -f $vesx) -ForegroundColor $DefaultColor
            # Check the MAC address
            $mac = Get-NetworkAdapter -VM $vesx | Select-Object MacAddress
            if ($mac.MacAddress -ne $macAddr) {
                Write-Host ("Wrong MAC address for {0}" -f $NewEsxName) -ForegroundColor $ErrorColor
                Write-Host ("Please set the MAC address of the VM {0} to {1}" -f $NewEsxName, $macAddr) -ForegroundColor $ErrorColor
                return
            }
        }
        catch {
            # The vESXi does not exist yet ! Compute information to this creation
            $availableInfo += @{"name" = $NewEsxName; "mac" = $macAddr; "ip" = $vConfig.ip_base + ($vConfig.ip_offset + $i) }
        }
    }
}
# Index to use the VM information when creating new VM
$availableIdx = 0

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
    for ($i = $onVesx.Count; $i -lt $e.nb_vesx; $i++, $availableIdx++) {
        if ($availableIdx -gt $availableInfo.Count) {
            Write-Host "No more IP available. Add new static IP in the DHCP and update 'dhcp_max_ip' in the configuration file!"
            return
        }
        Write-Host ("Creating the virtualized ESXi " + $availableInfo[$availableIdx].name) -ForegroundColor $DefaultColor
        if ($createFromClone) {
            # Create the vESXi from an existing vESXi
            $vesx = New-VM -VM $cloneSrc -VMHost $ip2obj[$e.ip] -Name $availableInfo[$availableIdx].name -DiskStorageFormat Thin
        }
        else {
            # Create the vESXi from OVF
            $vesx = Import-vApp -Source $vEsxOVF -VMHost $ip2obj[$e.ip] -Name $availableInfo[$availableIdx].name -DiskStorageFormat Thin
            $createFromClone = $true
            $cloneSrc = $vesx
        }
        # Set the MAC address
        $vesx | Get-NetworkAdapter | Set-NetworkAdapter -MacAddress $availableInfo[$availableIdx].mac -Confirm:$false -StartConnected:$true | Out-Null
        # Power on the vESXi
        Write-Host ("Power on the VM " + $availableInfo[$availableIdx].name) -ForegroundColor $DefaultColor
        $vesx | Start-VM | Out-Null
        Start-Sleep -Seconds 1
    }
}

$onVesx = Get-VM -Name "vesx*" | Where-Object { $_.PowerState -eq "PoweredOn" }
Write-Host ("Check connection of {0} vESXi" -f $onVesx.Count) -ForegroundColor $DefaultColor
$vesxNames = @()
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
        $vmh = Get-VMHost -Name $vesxIp
        if ($vmh.ConnectionState -ne "Connected") {
            Write-Host ("Please manually reconnect the host {0}" -f $vmh) -ForegroundColor $ErrorColor
        }
    }
    catch {
        $vesxNames += $vesxIp
    }
    # Wait to avoid overfilling the network
    Start-Sleep -Milliseconds 300
}
Write-Host ("Available vESXi: ") -ForegroundColor $DefaultColor
$vesxNames

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

# Assign vESXi to datacenters
$availableIdx = 0
foreach ($dc in Get-Datacenter -Name ($basenameDC + "*")) {
    Write-Host ("Configure the datacenter {0}" -f $dc) -ForegroundColor $DefaultColor
    $vesx = Get-VMHost -Location $dc
    for ($i = $vesx.Count; $i -lt $nbEsxPerDC; $i++, $availableIdx++) {
        # Connect vESXi to the datacenter
        Write-Host ("Connect {0} to the {1}" -f $vesxNames[$availableIdx], $dc) -ForegroundColor $DefaultColor
        $vmh = Add-VMHost -Name $vesxNames[$availableIdx] -Location $dc -User $vConfig.user -Password $vConfig.pwd -Force
        # Check the datastore configuration
        $ds = Get-Datastore -VMHost $vmh
        $dsName = "vDatastore" + $vesxNames[$availableIdx].split(".")[3]
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
                New-Datastore -VMHost $esx -Name ("vDatastore" + $esx.Name.Split(".")[3]) -Path $disks[0].ScsiLun -Vmfs -Confirm:$false | Out-Null
            }
        }
    }
}
# Enable Promiscuous mode to allow VM on nested ESXi to communicate
Write-Host "Allow the promiscuous mode on virtual switches" -F $DefaultColor
Get-VirtualSwitch -Standard | Where-Object { !(Get-SecurityPolicy -VirtualSwitch $_).AllowPromiscuous } | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true

# Create vSan Clusters
if ($vSanMode) {
    $dcs = Get-Datacenter -Name ($basenameDC + "*")
    Write-Host "Creating vSan clusters" -ForegroundColor $DefaultColor
    foreach ($d in $dcs) {
        Write-Host ("Creating the cluster {0}" -f ("vSan" + $d.Name)) -ForegroundColor $DefaultColor
        try {
            $cl = Get-Cluster -Name ("vSan" + $d.Name)
        }
        catch {
            $cl = New-Cluster -Name ("vSan" + $d.Name) -Location $d
        }
        Write-Host ("Configuring vESXi to create the vSan from the cluster {0}" -f $cl) -ForegroundColor $DefaultColor
        foreach ($vmh in (Get-VMHost -Location $d)) {
            Write-Host ("Configuring the vESXi {0}" -f $vmh) -ForegroundColor $DefaultColor
            Move-VMHost -VMHost $vmh -Destination $cl | Out-Null
            Write-Host "Enable vSan system" -ForegroundColor $DefaultColor
            $na = Get-VMHostNetworkAdapter -VMHost $vmh -VMKernel | Where-Object { ! $_.VsanTrafficEnabled }
            $na | Set-VMHostNetworkAdapter -VsanTrafficEnabled $true -Confirm:$false | Out-Null
            $dataDisk = $vmh | Get-VMHostDisk | Where-Object { $_.TotalSectors -eq 83886080 }
            if ($dataDisk.ScsiLun.VsanStatus -eq "Eligible") {
                Write-Host "Configuring disks" -ForegroundColor $DefaultColor
                $cacheDisk = $vmh | Get-VMHostDisk | Where-Object { $_.TotalSectors -eq 20971520 }
                # Use RunAsync to run this task in order to avoid weird error (bug ?)
                $task = New-VsanDiskGroup -VMHost $vmh -DataDiskCanonicalName $dataDisk -SsdCanonicalName $cacheDisk -RunAsync
                while ($task.state -eq "Running") {
                    Start-Sleep -Seconds 10
                    $task = Get-Task -ID $task.id
                }
            }
        }
        if (!$cl.VsanEnabled) {
            Write-Host ("Configuring the vSan for the cluster {0}" -f ("vSan" + $d.Name)) -ForegroundColor $DefaultColor
            Set-Cluster -Cluster $cl -VsanEnabled:$true -Confirm:$false | Out-Null
        }
    }
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