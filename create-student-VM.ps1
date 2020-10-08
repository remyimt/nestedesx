# Every error stops the script immediately
$ErrorActionPreference = "Stop"

# The header reads the configuration file ($config variable)
& "$PSScriptRoot/header.ps1"

# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd
# vESXi configuration : root account and password
$vConfig = $config.virtual_esx
# Path to the OVF file to deploy
$studentOVF = $config.architecture.student_ovf
# Name of the new VM
$studentVMName = $config.architecture.student_vm_name

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

# Get the running ESXi VM (vESXi)
$onVesx = Get-VM -Name ($vConfig.basename + "*") | Where-Object { $_.PowerState -eq "PoweredOn" } | Sort-Object -Property "Name"


# Create one student VM on every vESXi
$nbStudentVM = (Get-VM -Name ($studentVMName + "*")).Count
foreach ($v in $onVesx) {
        Write-Host ("Get the vESXi associated to {0}" -f $v) -ForegroundColor $DefaultColor
        $esxName = $v.Guest.IPAddress[0]
        try {
            $myVM = Get-VM -Name ($studentVMName + "*") -Location $esxName
            if ( $myVM.Count -eq 0 ) {
                $vmh = Get-VMHost -Name $esxName
                if ( $vmh.ConnectionState -eq "Connected" ) {
                    $nbStudentVM++
                    Write-Host ("Create the student VM on {0}" -f $esxName) -ForegroundColor $DefaultColor
                    if ($createFromClone) {
                        # Create the student VM from an existing VM
                        $studentVM = New-VM -VM $cloneSrc -VMHost $vmh -Name ($studentVMName + $nbStudentVM) -DiskStorageFormat Thin
                    }
                    else {
                        # Create the student VM from OVF
                        $studentVM = Import-vApp -Source $studentOVF -VMHost $vmh -Name ($studentVMName + $nbStudentVM) -DiskStorageFormat Thin
                        $createFromClone = $true
                        $cloneSrc = $studentVM
                    }
                } else {
                    Write-Host ("vESXi {0} is not connected!" -f $esxName) -ForegroundColor $ErrorColor
                }
            } else {
                    Write-Host ("Student {0} already exists!" -f $studentVMName) -ForegroundColor $ErrorColor
            }
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor $ErrorColor
            Write-Host ("vESXi {0} does not exist: run './deploy.ps1" -f $esxName) -ForegroundColor $ErrorColor
        }
}
