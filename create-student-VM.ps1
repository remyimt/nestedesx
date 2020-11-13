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

# Create a new VM on every vESXi (ESXi VM)
$vmhs = @()
# Get all VMHost associated to running vESXi
#$onVesx = Get-VM -Name ($vConfig.basename + "*") | Where-Object { $_.PowerState -eq "PoweredOn" } | Sort-Object -Property "Name"
#foreach ($v in $onVesx) {
#        Write-Host ("Get the vESXi associated to {0}" -f $v) -ForegroundColor $DefaultColor
#        $esxName = $v.Guest.IPAddress[0]
#        try {
#            $myVM = Get-VM -Name ($studentVMName + "*") -Location $esxName
#            if ( $myVM.Count -eq 0 ) {
#                $vmh = Get-VMHost -Name $esxName
#                if ( $vmh.ConnectionState -eq "Connected" ) {
#                    $vmhs += $vmh
#                }
#            }
#        } catch {
#            Write-Host $_.Exception.Message -ForegroundColor $ErrorColor
#            Write-Host ("vESXi {0} does not exist: run './deploy.ps1" -f $esxName) -ForegroundColor $ErrorColor
#        }
#}

# Create a new VM on every student datacenter
$vmhs = @()
# Get one running ESXi VM (vESXi) per datacenter
Get-Datacenter -Name ($config.architecture.new_dc_basename + "*") | ForEach-Object { $vmhs += Get-VMHost -Location $_ | Select-Object -First 1 }

# Create one student VM on every selected vESXi
$nbStudentVM = 0
foreach ($vmh in $vmhs) {
    $nbStudentVM++
    try {
        $myvm = Get-VM -Name ($studentVMName + $nbStudentVM)
        Write-Host ("VM {0} already exists!" -f $myvm.Name) -ForegroundColor $DefaultColor
    }
    catch {
        if ($vmh.ConnectionState -eq "Connected") {
            Write-Host ("Create the student VM on {0}" -f $vmh.Name) -ForegroundColor $DefaultColor
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
            Write-Host ("vESXi {0} is not connected!" -f $vmh.Name) -ForegroundColor $ErrorColor
        }
    }
}
