#Requires -Version 5.1
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
$scenario = if ($args.Count -ge 1) { $args[0] } else { "compute" }
$ok = @("compute", "texture", "pointer", "cli", "fs", "tcp")
if ($ok -notcontains $scenario) {
    throw "usage: build.ps1 {compute|texture|pointer|cli|fs|tcp}"
}
Copy-Item "scenarios\$scenario.mbt" "gen\world\guest\run.mbt" -Force
moon build --target wasm --release
if ($LASTEXITCODE -ne 0) { throw "moon build failed ($LASTEXITCODE)" }
New-Item -ItemType Directory -Force dist | Out-Null
$core = "_build\wasm\release\build\gen\gen.wasm"
if (-not (Test-Path $core)) { throw "moon did not produce $core" }
wasm-tools component embed wit $core --encoding utf16 -o _build\embedded.wasm
if ($LASTEXITCODE -ne 0) { throw "wasm-tools component embed failed" }
wasm-tools component new _build\embedded.wasm -o "dist\$scenario.wasm"
if ($LASTEXITCODE -ne 0) { throw "wasm-tools component new failed" }
Write-Host "wrote dist\$scenario.wasm"
