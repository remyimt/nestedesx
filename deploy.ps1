# Every error stops the script immediately
$ErrorActionPreference = "Stop"
# Beautiful colors
$DefaultColor = "DarkGray"
$ErrorColor = "Red"

Write-Host "Welcome ! My First PowerCLI Script:" -ForegroundColor  $DefaultColor

Write-Host "Read the configuration file"
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
Write-Host "== Physical ESXi Configuration ==" -ForegroundColor $DefaultColor
# Add ESXi
Write-Host "Configuring ESXi:" -ForegroundColor $DefaultColor
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
Write-Host "== Virtualized ESXi Configuration ==" -ForegroundColor $DefaultColor
# Create VM from OVF
$nbNewEsx = 1
foreach ($e in $esxConfig) {
    try {
        $cloneSrc = Get-VM -Name ($vConfig.basename + 1)
        $createFromClone = $true
    }
    catch {
        $createFromClone = $false
    }
    for ($i = 0; $i -lt $e.nb_vesx; $i++) {
        # Compute the MAC address
        if ($nbNewEsx -lt 10) {
            $macAddr = "00:50:56:a1:00:0" + $nbNewEsx
        }
        else {
            $macAddr = "00:50:56:a1:00:" + $nbNewEsx
        }
        # Compute the vESXi name
        $NewEsxName = $vConfig.basename + $nbNewEsx
        # Retrieve the vESXi
        try {
            $newEsx = Get-VM -Name $NewEsxName
            # Check the MAC address
            $mac = Get-NetworkAdapter -VM $newEsx | Select-Object MacAddress
            if ($mac.MacAddress -ne $macAddr) {
                Write-Host ("Wrong MAC address for {0}" -f $NewEsxName) -ForegroundColor $ErrorColor
                Write-Host ("Please set the MAC address of the VM {0} to {1}" -f $NewEsxName, $macAddr) -ForegroundColor $ErrorColor
                return
            }
            # Check the host
            if ($ip2obj[$e.ip] -ne (Get-VMHost -VM $newEsx)) {
                Write-Host ("Wrong host for {0}" -f $NewEsxName) -ForegroundColor $ErrorColor
                Write-Host ("Please set the host of the VM {0} to {1}" -f $NewEsxName, $ip2obj[$e.ip]) -ForegroundColor $ErrorColor
            }
        }
        catch {
            # Create the vESXi from OVF
            Write-Host ("Creating the virtualized ESXi " + $NewEsxName) -ForegroundColor $DefaultColor
            if ($createFromClone) {
                $newEsx = New-VM -VM $cloneSrc -VMHost $ip2obj[$e.ip] -Name $NewEsxName -DiskStorageFormat Thin
            }
            else {
                $newEsx = Import-vApp -Source $vEsxOVF -VMHost $ip2obj[$e.ip] -Name $NewEsxName -DiskStorageFormat Thin
                $createFromClone = $true
                $cloneSrc = $newEsx
            }
            # Set the MAC address
            $newEsx | Get-NetworkAdapter | Set-NetworkAdapter -MacAddress $macAddr -Confirm:$false -StartConnected:$true | Out-Null
        }
        if ($newEsx.PowerState -eq "PoweredOff") {
            Write-Host ("Power on the VM " + $NewEsxName) -ForegroundColor $DefaultColor
            $newEsx | Start-VM | Out-Null
        }
        $nbNewEsx++
    }
}
$nbNewEsx--
Write-Host "Waiting the vESX" -ForegroundColor $DefaultColor
for ($i = 1; $i -le $nbNewEsx; $i++) {
    $vesxIP = $vConfig.ip_base + ($vConfig.ip_offset + $i)
    $oReturn = Test-Connection -computername $vesxIP -Count 1 -quiet
    while (!$oReturn) {
        Start-Sleep -Seconds 20
        $oReturn = Test-Connection -computername $vesxIP -Count 1 -quiet
    }
    # Wait to avoid overfilling the network
    Start-Sleep -Milliseconds 300
}
Write-Host "Create datacenters for the vESXi" -ForegroundColor $DefaultColor
if ($nbNewEsx % $nbEsxPerDC -eq 0) {
    $nbDC = $nbNewEsx / $nbEsxPerDC
}
else {
    $nbDC = [math]::Truncate($nbNewEsx / $nbEsxPerDC) + 1
}
for ($i = 1; $i -le $nbDC; $i++) {
    $dcName = $basenameDC + $i
    try {
        $dc = Get-Datacenter -Name $dcName
        Write-Host ("Datacenter {0} already exists" -f $dcName) -ForegroundColor $DefaultColor
    }
    catch {
        Write-Host ("Create a new datacenter" + $dcName) -ForegroundColor $DefaultColor
        $folder = Get-Folder -NoRecursion
        $dc = New-Datacenter -Location $folder -Name $dcName
    }
}
Write-Host "Add vESXi to datacenters " -ForegroundColor $DefaultColor
$dcNumber = 0
for ($i = 1; $i -le $nbNewEsx; $i++) {
    if (($i - 1) % $nbEsxPerDC -eq 0) {
        $dc = Get-Datacenter -Name ($basenameDC + ++$dcNumber)
    }
    $vesxIP = $vConfig.ip_base + ($vConfig.ip_offset + $i)
    Write-Host ("Add vESXi {0} to {1}" -f $vesxIP, $dc.Name) -ForegroundColor $DefaultColor
    try {
        $ip2obj[$e.ip] = Get-VMHost -Name $vesxIP -Location $dc
        Write-Host ("vESXi {0} is already connected" -f $vesxIP) -ForegroundColor $DefaultColor
    }
    catch {
        Write-Host ("Add the host {0} to {1}" -f $vesxIP, $dc.Name) -ForegroundColor $DefaultColor
        $ip2obj[$vesxIP] = Add-VMHost -Name $vesxIP -Location $dc -User $vConfig.user -Password $vConfig.pwd -Force
        $ds = Get-Datastore -VMHost $ip2obj[$vesxIP]
        $dsName = "vDatastore" + $i
        if ($ds.Count -gt 0) {
            if ($ds.Name -ne $dsName) {
                Write-Host ("Removing the datastore of {0}" -f $vesxIP) -ForegroundColor $DefaultColor
                Remove-Datastore -VMHost $ip2obj[$vesxIP] -Datastore $ds -Confirm:$false | Out-Null
                Write-Host ("Creating a new datastore for {0}" -f $vesxIP) -ForegroundColor $DefaultColor
                New-Datastore -VMHost $ip2obj[$vesxIP] -Name $dsName -Path mpx.vmhba0:C0:T0:L0 -Vmfs -Confirm:$false | Out-Null
            }
        }
        elseif ($alwaysDatastore) {
            # Create a datastore from the smallest disk
            Write-Host ("Creating a new datastore for {0}" -f $vesxIP) -ForegroundColor $DefaultColor
            $disks = Get-VMHostDisk -VMHost $ip2obj[$vesxIP] | Sort-Object -Property TotalSectors
            New-Datastore -VMHost $ip2obj[$vesxIP] -Name $dsName -Path $disks[0].ScsiLun -Vmfs -Confirm:$false | Out-Null
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
            Set-Cluster -Cluster $cl -VsanEnabled:$true -Confirm:$false
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