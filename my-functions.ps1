# Function used in deploy.ps1 and set-permissions.ps1
function NameFromMAC {
    param (
        [string]
        $macAddr
    )
    $array = $macAddr.Split(":")
    return $vConfig.basename + ("{0:d3}" -f [int]("0x{0}" -f $array[5]))
}

# Function used in delete-infra.ps1 and shutdown-vms.ps1
function uselessVM {
    param (
        [string]
        $anotherPattern
    )
    $adminPattern = @('dhcp', 'gateway', 'manager', 'nsx', 'vCenter')
    if($anotherPattern -ne '' ) {
        $adminPattern += $anotherPattern
    }
    $allVM = Get-VM | Where-Object { (Get-VMHost -VM $_).ConnectionState -eq "Connected" }
    $adminVM = @()
    foreach($pattern in $adminPattern) {
        $adminVM += $allVM | Where-Object { $_.Name -match $pattern }
    }
    return $allVM | Where-Object { $adminVM -notcontains $_ }
}
