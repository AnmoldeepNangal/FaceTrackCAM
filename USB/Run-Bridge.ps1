[CmdletBinding()]
param([int]$LocalPort = 18080, [string]$DeviceID = '', [int]$MuxPort = 27015)
$ErrorActionPreference = 'Stop'
$mutex = New-Object System.Threading.Mutex($false, "Local\FacePullBridge-$LocalPort")
if (-not $mutex.WaitOne(0)) { exit 0 }
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'FacePullBridge.cs')
    [FacePullBridge]::Run($LocalPort, $MuxPort, $DeviceID)
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }

