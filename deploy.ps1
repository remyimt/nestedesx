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
# List of physical ESX available (ping)
$pEsx = @()
$ip2obj = @{ }
# List of virtualized ESX
$vEsx = @()
# ESXi Cluster Name
$datacenter = "SchoolDatacenter"
$physicalCluster = "PhysicalESX"
$vEsxOVF = "./Files/vesx-ovf/vesx-template/vesx-template.ovf"

# Connection to vSphere
Write-Host "Connecting to vSphere" -ForegroundColor $DefaultColor
Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd

Write-Host "== Physical ESXi Configuration =="
# Add ESXi
Write-Host "Configuring ESXi:" -ForegroundColor $DefaultColor
foreach ($e in $esxConfig) {
    $oReturn = Test-Connection -computername $e.ip -Count 1 -quiet
    switch ($oReturn) {
        $true {
            Write-Host ("+ Add {0} to the ESXi list" -f $e.ip) -ForegroundColor $DefaultColor
            $pEsx += $e
        }
        $false {
            Write-Host ("- Remove {0} from the ESXi list" -f $e.ip) -ForegroundColor $ErrorColor
        }
        Default {
            Write-Host ("- Remove {0} from the ESXi list" -f $e.ip) -ForegroundColor $ErrorColor
        }
    }
}
Write-Host $pEsx.Count "ESXi available:" -ForegroundColor $DefaultColor
$pEsx.foreach{
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
    $cl = New-Cluster -Name $physicalCluster -Location $dc
}
foreach ($e in $pEsx) {
    try {
        $ip2obj[$e.ip] = Get-VMHost -Name $e.ip -Location $physicalCluster
    }
    catch {
        Write-Host ("Add the host {0} to $physicalCluster" -f $e.ip) -ForegroundColor $DefaultColor
        $ip2obj[$e.ip] = Add-VMHost -Name $e.ip -Location $physicalCluster -User $e.user -Password $e.pwd -Force
    }
}
Write-Host "== Virtualized ESXi Configuration ==" -ForegroundColor $DefaultColor
# Create VM from OVF
$nbNewEsx = 1
foreach ($e in $pEsx) {
    for ($i = 0; $i -lt $e.nb_vesx; $i++) {
        # Create one vESXi
        $NewEsxName = "vesx" + $nbNewEsx
        try {
            $newEsx = Get-VM -Name $NewEsxName
        }
        catch {
            Write-Host ("Creating the virtualized ESXi " + $NewEsxName) -ForegroundColor $DefaultColor
            $newEsx = Import-vApp -Source $vEsxOVF -VMHost $ip2obj[$e.ip] -Name $NewEsxName -DiskStorageFormat Thin
            if ($nbNewEsx -lt 10) {
                $trash = $newEsx | Get-NetworkAdapter | Set-NetworkAdapter -MacAddress ("00:50:56:a1:00:0" + $nbNewEsx) -Confirm:$false -StartConnected:$true
            }
            else {
                $trash = $newEsx | Get-NetworkAdapter | Set-NetworkAdapter -MacAddress ("00:50:56:a1:00:" + $nbNewEsx) -Confirm:$false -StartConnected:$true
            }
        }
        if ($newEsx.PowerState -eq "PoweredOff") {
            Write-Host ("Power on the VM " + $NewEsxName) -ForegroundColor $DefaultColor
            $trash = $newEsx | Start-VM
        }
        $nbNewEsx++
    }
}
Write-Host "Waiting the vESX" -ForegroundColor $DefaultColor
for ($i = 1; $i -lt $nbNewEsx; $i++) {
    $oReturn = $false
    while (!$oReturn) {
        $oReturn = Test-Connection -computername ("192.168.1." + (20 + $i)) -Count 1 -quiet
        Start-Sleep -Seconds 20
    }
}

<#
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
#>
