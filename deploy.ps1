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
$esx = $config.physical_esx
# Files to upload on datastores
$fileFolder = "./Files"
$esxInstallerPattern = "VMware-VMvisor-Installer*.iso"
# Objects representing the physical ESXi
$pEsx = @()
# vCenter VM host
$vcenterHost = $null
# Objects representing the virtualized ESXi
$vEsx = @()
# ESXi Cluster Name
$datacenter = "SchoolDatacenter"
$physicalCluster = "PhysicalESX"
$virtualCluster = "VirtualESX"
$vmCluster = "VirtualMachines"

### Function Definitions
Function uploadFile {
    param (
        [Parameter(Mandatory)]
        [string]
        $filename, 
        [Parameter(Mandatory)]
        [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]
        $datastore
    )
    Write-Host ("Looking for {0} on datastore {1}" -f $filename, $datastore.Name) -ForegroundColor $DefaultColor
    $myFile = Get-ChildItem -Path $datastore.DatastoreBrowserPath | Where-Object { $_.Name -like $filename }
    if ($myFile.Count -eq 0) {
        Write-Host "Upload the file on" $datastore.Name -ForegroundColor $DefaultColor
        $copyFile = Copy-DatastoreItem -Item $fileFolder/$filename -Destination $datastore.DatastoreBrowserPath
    }
    else {
        Write-Host ("{0} exists on {1}") -f $filename, $datastore -ForegroundColor $DefaultColor
        $copyFile = $myFile[0]
    }
    $copyFile
}
### End of functions

# Connection to vSphere
Write-Host "Connecting to vSphere" -ForegroundColor $DefaultColor
Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd

Write-Host "== Physical ESXi Configuration =="
# Add ESXi
Write-Host "Configuring ESXi:" -ForegroundColor $DefaultColor
$esxReady = @()
foreach ($e in $esx) {
    $oReturn = Test-Connection -computername $e.ip -Count 1 -quiet
    switch ($oReturn) {
        $true {
            Write-Host ("+ Add {0} to the ESXi list" -f $e.ip) -ForegroundColor $DefaultColor
            $esxReady += $e
        }
        $false {
            Write-Host ("- Remove {0} from the ESXi list" -f $e.ip) -ForegroundColor $ErrorColor
        }
        Default {
            Write-Host ("- Remove {0} from the ESXi list" -f $e.ip) -ForegroundColor $ErrorColor
        }
    }
}
Write-Host $esxReady.Count "ESXi available:" -ForegroundColor $DefaultColor
$esxReady.foreach{
    Write-Host $_.ip -ForegroundColor $DefaultColor
}

Write-Host "Retrieve the cluster $physicalCluster" -ForegroundColor $DefaultColor
$dc = Get-Datacenter
if (!$dc) {
    Write-Host "Create a new datacenter" -ForegroundColor $DefaultColor
    $folder = Get-Folder -NoRecursion
    $dc = New-Datacenter -Location $folder -Name $datacenter
}
Try {
    $cl = Get-Cluster -Name $physicalCluster
}
Catch {
    Write-Host "Create the cluster" -ForegroundColor $DefaultColor
    $cl = New-Cluster -Name $physicalCluster
    -Location $dc
}
foreach ($e in $esxReady) {
    try {
        $h = Get-VMHost -Name $e.ip -Location $physicalCluster
    }
    catch {
        Write-Host ("Add the host {0} to $physicalCluster" -f $e.ip) -ForegroundColor $DefaultColor
        $h = Add-VMHost -Name $e.ip -Location $physicalCluster -User $e.user -Password $e.pwd -Force
    }
    $vm = Get-VM -Name "*vCenter-Server-Appliance*"
    if ($h.Id -eq $vm.VMHostId) {
        Write-Host ("vCenter on {0}" -f $e.ip) -ForegroundColor $DefaultColor
        $vcenterHost = $h
    }
    else {
        $pEsx += $h
    }
}
# Copy ISO files on datastores
Write-Host ("{0} physical ESXi and {1} as vCenter host" -f $pEsx.Count, $vcenterHost) -ForegroundColor $DefaultColor
$st = Get-Datastore
# DatastoreId = full_path - Use the full path to mount the ISO file
$id2path = @{ } 
$firstSt, $otherSt = $st
Write-Host ("Looking for {0} on datastore {1}" -f $esxInstallerPattern, $firstSt.Name) -ForegroundColor $DefaultColor
$myFile = Get-ChildItem -Path $firstSt.DatastoreBrowserPath | Where-Object { $_.Name -like $esxInstallerPattern }
if ($myFile.Count -eq 0) {
    Write-Host "Upload the file on" $firstSt.Name -ForegroundColor $DefaultColor
    Copy-DatastoreItem -Item $fileFolder/$esxInstallerPattern -Destination $firstSt.DatastoreBrowserPath
    # Get the file for later copy
    $myFile = Get-ChildItem -Path $firstSt.DatastoreBrowserPath | Where-Object { $_.Name -like $esxInstallerPattern }
}
else {
    Write-Host ("{0} exists on {1}" -f $esxInstallerPattern, $firstSt.Name) -ForegroundColor $DefaultColor
}
$copyFile = $myFile[0]
$id2path[$copyFile.DatastoreId] = $copyFile.DatastoreFullPath

foreach ($o in $otherSt) {
    Write-Host ("Looking for {0} on datastore {1}" -f $esxInstallerPattern, $o.Name) -ForegroundColor $DefaultColor
    $myFile = Get-ChildItem -Path $o.DatastoreBrowserPath | Where-Object { $_.Name -like $esxInstallerPattern }
    if ($myFile.Count -eq 0) {
        Write-Host ("Upload the file on {0} from {1}" -f $o.Name, $firstSt.Name) -ForegroundColor $DefaultColor
        Copy-DatastoreItem -Item $copyFile -Destination $o.DatastoreBrowserPath
        $myFile = Get-ChildItem -Path $o.DatastoreBrowserPath | Where-Object { $_.Name -like $esxInstallerPattern }
    }
    else {
        Write-Host ("{0} exists on {1}" -f $esxInstallerPattern, $o.Name) -ForegroundColor $DefaultColor
    }
    $id2path[$myFile[0].DatastoreId] = $myFile[0].DatastoreFullPath
}
Write-Host "== Virtualized ESXi Configuration ==" -ForegroundColor $DefaultColor
<#
foreach ($h in $pEsx) {
    $st = Get-Datastore -Id $h.DatastoreIdList[0]
        $vm = Get-VM -Name "TestVM"
    #$vm = New-VM -Name "TestVM" -ResourcePool $h -NumCPU 2 -MemoryGB 4 -DiskGB 40 -NetworkName "VM Network" -CD -DiskStorageFormat Thin
    $cd = Get-CDDrive -VM $vm
    $isopath = "{0}/Win10_1903_V2_English_x64.iso" -f $st.DatastoreBrowserPath
    Set-CDDrive -CD $cd -IsoPath $isopath -StartConnected $true -Confirm:$false
}
#>
