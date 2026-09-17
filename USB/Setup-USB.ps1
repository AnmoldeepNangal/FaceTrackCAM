[CmdletBinding()]
param([switch]$NoAutoStart)
$ErrorActionPreference = 'Stop'
$install = Join-Path $env:LOCALAPPDATA 'FacePull\USB'
New-Item -ItemType Directory -Force -Path $install | Out-Null
foreach ($name in @('FacePullBridge.cs','Run-Bridge.ps1','Start-USB.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $install $name) -Force
}
if (-not $NoAutoStart) {
    $startup = [Environment]::GetFolderPath('Startup')
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path $startup 'FacePull USB.lnk'))
    $link.TargetPath = (Get-Command powershell.exe).Source
    $link.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $install 'Start-USB.ps1')`""
    $link.WindowStyle = 7
    $link.Save()
}
& (Join-Path $install 'Start-USB.ps1')
if (-not (Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue)) {
    Write-Host 'Install Apple Devices from the Microsoft Store, open it, and trust the connected iPhone.'
}
Write-Host 'Setup complete. Copy the USB URL from FacePull Settings > Connect into OBS once.'

