[CmdletBinding()]
param(
    [string]$IProxyPath,
    [ValidateRange(1024, 65535)][int]$LocalPort = 18080,
    [string]$DeviceID
)
$ErrorActionPreference = 'Stop'
if (-not $IProxyPath) {
    $localTool = Join-Path $PSScriptRoot 'iproxy.exe'
    if (Test-Path -LiteralPath $localTool) { $IProxyPath = $localTool }
    else {
        $command = Get-Command iproxy.exe -ErrorAction SilentlyContinue
        if ($command) { $IProxyPath = $command.Source }
    }
}
if (-not $IProxyPath -or -not (Test-Path -LiteralPath $IProxyPath)) {
    throw 'iproxy is required. Place a trusted libusbmuxd iproxy.exe and its DLLs in this USB folder, or pass -IProxyPath. See README.md for the upstream source.'
}
$IProxyPath = (Resolve-Path -LiteralPath $IProxyPath).Path
$bridgeArguments = @('-l', '127.0.0.1')
if ($DeviceID) { $bridgeArguments += @('-u', $DeviceID) }
$bridgeArguments += "${LocalPort}:8080"
Write-Host 'Connect the iPhone by USB, unlock it, and trust this computer.'
Write-Host 'Start streaming in FaceTrackCam. Keep the app open.'
Write-Host "Use the USB URL from the app in OBS (local port $LocalPort)."
Write-Host 'Keep this window open. Press Ctrl+C to stop the bridge.'
& $IProxyPath @bridgeArguments
if ($LASTEXITCODE -ne 0) { throw "USB bridge exited with code $LASTEXITCODE. Check the cable, trust prompt, Apple device support, and iproxy version." }
