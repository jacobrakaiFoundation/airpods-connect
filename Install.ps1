<#
  Install.ps1 - installs Connect-AirPods for the current user.

  Copies Connect-AirPods.ps1 to %LOCALAPPDATA%\AirPodsConnect and adds a
  "Connect AirPods" shortcut to the Desktop and the Start menu. No admin needed.

  Usage:
    Install.ps1                     install (or update)
    Install.ps1 -Name "Sony"        shortcut connects a different headset
    Install.ps1 -NoDesktop          Start menu shortcut only
    Install.ps1 -Uninstall          remove the files and shortcuts

  Run from a clone or download, or straight from GitHub:
    irm https://raw.githubusercontent.com/jacobrakaiFoundation/airpods-connect/main/Install.ps1 | iex
#>
param(
    [string]$Name = 'AirPods',
    [switch]$NoDesktop,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'AirPodsConnect'
$script = Join-Path $installDir 'Connect-AirPods.ps1'
$shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Connect AirPods.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Connect AirPods.lnk')
)

if ($Uninstall) {
    $shortcuts | Where-Object { Test-Path $_ } | Remove-Item
    if (Test-Path $installDir) { Remove-Item -Recurse $installDir }
    Write-Output 'Connect AirPods removed.'
    return
}

New-Item -ItemType Directory -Force $installDir | Out-Null

# Next to this file when run from a clone; otherwise (irm | iex) fetch it from GitHub.
$source = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Connect-AirPods.ps1' }
if ($source -and (Test-Path $source)) {
    Copy-Item $source $script -Force
} else {
    Invoke-WebRequest -UseBasicParsing -OutFile $script `
        'https://raw.githubusercontent.com/jacobrakaiFoundation/airpods-connect/main/Connect-AirPods.ps1'
}
# Downloaded files carry a Mark of the Web; clear it so the shortcut runs without a prompt.
Unblock-File $script

$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
if ($Name -ne 'AirPods') { $arguments += " -Name `"$Name`"" }

$shell = New-Object -ComObject WScript.Shell
foreach ($path in $shortcuts) {
    if ($NoDesktop -and $path -eq $shortcuts[1]) {
        if (Test-Path $path) { Remove-Item $path }
        continue
    }
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments = $arguments
    $lnk.WorkingDirectory = $installDir
    $lnk.IconLocation = "$env:SystemRoot\System32\mmres.dll,-3011"
    $lnk.WindowStyle = 7
    $lnk.Description = "Connect $Name over Bluetooth"
    $lnk.Save()
}

# Build the helper DLL now so the first click is as fast as the rest.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Name $Name -Quiet

Write-Output "Installed. Use the 'Connect AirPods' shortcut in the Start menu$(if (-not $NoDesktop) { ' or on the Desktop' })."
