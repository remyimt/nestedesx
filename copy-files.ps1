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
