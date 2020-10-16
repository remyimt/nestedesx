# Function used in deploy.ps1 and set-permissions.ps1
function NameFromMAC {
    param (
        [string]
        $macAddr
    )
    $array = $macAddr.Split(":")
    return $vConfig.basename + ("{0:d3}" -f [int]("0x{0}" -f $array[5]))
}

