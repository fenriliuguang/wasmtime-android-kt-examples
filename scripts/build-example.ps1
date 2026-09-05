#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$Example,
    [switch]$Install
)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

switch ($Example) {
    "cube" { Set-Location "$Root\guests\rotating-cube"; .\build.ps1 }
    "border2d" { Set-Location "$Root\guests\boundary-2d"; .\build.ps1 }
    { $_ -in @("compute", "texture", "pointer", "cli", "fs", "tcp") } {
        Set-Location "$Root\guests\kit"; .\build.ps1 $Example
    }
    "http-tcp" { Set-Location "$Root\guests\http-tcp"; .\build.ps1 }
    default { throw "unknown example: $Example" }
}

$Task = if ($Install) { ":app:installDebug" } else { ":app:assembleDebug" }
Set-Location "$Root\hosts\fullscreen-surface"
.\gradlew.bat $Task "-Pexample=$Example"
Write-Host "ok example=$Example"
