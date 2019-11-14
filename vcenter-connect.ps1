# Read the confiugration file
$config = Get-Content -Raw -Path configuration.json | ConvertFrom-Json
# vSphere Account
$vcenterIp = $config.vcenter.ip
$vcenterUser = $config.vcenter.user
$vcenterPwd = $config.vcenter.pwd

Write-Host "Connecting to vCenter"
$oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
while (!$oReturn) {
    Write-Host "Test the vCenter connection"
    Start-Sleep -Seconds 30
    $oReturn = Connect-VIServer -Server $vcenterIp -User $vcenterUser -Password $vcenterPwd
}
