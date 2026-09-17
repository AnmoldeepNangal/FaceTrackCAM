[CmdletBinding()]
param([string]$DeviceID = '')
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Run-Bridge.ps1'
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
if ($DeviceID) {
    if ($DeviceID -notmatch '^[A-Za-z0-9-]+$') { throw 'Invalid device ID' }
    $arguments += " -DeviceID $DeviceID"
}
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "$arguments -LocalPort 18080 -DevicePort 8080"
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "$arguments -LocalPort 18554 -DevicePort 8554"
Write-Host 'FacePull USB bridges started at 127.0.0.1:18080 and 127.0.0.1:18554.'
Write-Host 'Connect your iPhone, trust this computer, and start streaming in FacePull.'

