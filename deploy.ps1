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
$datacenter = "SchoolDatacenter"
$vEsxOVF = "./Files/vesx-ovf/vesx1/vesx1.ovf"
# Number of vESXi per datacenter
$nbEsxPerDC = 3
# Offset for IP address of vESXi
$ipOffset = 40
# New Datacenter basename
$basenameDC = "G"

# Connection to vSphere
Write-Host "Connecting to vSphere" -ForegroundColor $DefaultColor
Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd

Write-Host "== Physical ESXi Configuration =="
# Add ESXi
Write-Host "Configuring ESXi:" -ForegroundColor $DefaultColor
$missing = @()
foreach ($e in $esxConfig) {
    $oReturn = Test-Connection -computername $e.ip -Count 1 -quiet
    if (!$oReturn) {
        $missing += $e
    }
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
        $ip2obj[$e.ip] = Add-VMHost -Name $e.ip -Location $datacenter -User $e.user -Password $e.pwd
    }
}
Write-Host "== Virtualized ESXi Configuration ==" -ForegroundColor $DefaultColor
# Create VM from OVF
$nbNewEsx = 1
foreach ($e in $esxConfig) {
    for ($i = 0; $i -lt $e.nb_vesx; $i++) {
        if ($nbNewEsx -lt 10) {
            $macAddr = "00:50:56:a1:00:0" + $nbNewEsx
        }
        else {
            $macAddr = "00:50:56:a1:00:" + $nbNewEsx
        }
        # Create one vESXi
        $NewEsxName = "vesx" + $nbNewEsx
        try {
            $newEsx = Get-VM -Name $NewEsxName
            $mac = Get-NetworkAdapter -VM $newEsx | Select-Object MacAddress
            if ($mac.MacAddress -ne $macAddr) {
                Write-Host ("Wrong MAC for {0}" -f $NewEsxName) -ForegroundColor $ErrorColor
                Write-Host ("Please set MAC address of the VM {0} to {1}" -f $NewEsxName, $macAddr) -ForegroundColor $ErrorColor
                return
            }
        }
        catch {
            Write-Host ("Creating the virtualized ESXi " + $NewEsxName) -ForegroundColor $DefaultColor
            $newEsx = Import-vApp -Source $vEsxOVF -VMHost $ip2obj[$e.ip] -Name $NewEsxName -DiskStorageFormat Thin
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
    $vesxIP = "192.168.1." + ($ipOffset + $i)
    $oReturn = Test-Connection -computername $vesxIP -Count 1 -quiet
    while (!$oReturn) {
        Start-Sleep -Seconds 20
        $oReturn = Test-Connection -computername $vesxIP -Count 1 -quiet
    }
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
Write-Host ("Add vESXi to the datacenter " + $dcName) -ForegroundColor $DefaultColor
$dcNumber = 0
for ($i = 1; $i -le $nbNewEsx; $i++) {
    if (($i - 1) % $nbEsxPerDC -eq 0) {
        $dc = Get-Datacenter -Name ($basenameDC + ++$dcNumber)
    }
    $vesxIP = "192.168.1." + ($ipOffset + $i)
    try {
        $ip2obj[$e.ip] = Get-VMHost -Name $vesxIP -Location $dc
        Write-Host ("vESXi {0} is already connected" -f $vesxIP) -ForegroundColor $DefaultColor
    }
    catch {
        Write-Host ("Add the host {0} to {1}" -f $vesxIP, $dc.Name) -ForegroundColor $DefaultColor
        $ip2obj[$vesxIP] = Add-VMHost -Name $vesxIP -Location $dc -User $vConfig.user -Password $vConfig.pwd -Force
        Write-Host ("Removing the datastore of {0}" -f $vesxIP) -ForegroundColor $DefaultColor
        $ds = Get-Datastore -Id $ip2obj[$vesxIP].DatastoreIdList[0]
        Remove-Datastore -VMHost $ip2obj[$vesxIP] -Datastore $ds -Confirm:$false
        Write-Host ("Creating a new datastore for {0}" -f $vesxIP) -ForegroundColor $DefaultColor
        $ds = New-Datastore -VMHost $ip2obj[$vesxIP] -Name ("vDatastore" + $i) -Path mpx.vmhba0:C0:T0:L0 -Vmfs -Confirm:$false
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
