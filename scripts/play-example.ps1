#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$Example,
    [int]$TimeoutSec = 30
)
$ErrorActionPreference = "Stop"
$PkgBase = "io.github.fenriliuguang.wasmtime.android.examples.fullscreen"
$map = @{
    "cube"     = @{ Pkg = $PkgBase; Act = ".MainActivity"; Tag = "FullscreenSurface"; Expect = "" }
    "border2d" = @{ Pkg = "$PkgBase.border2d"; Act = ".Border2dActivity"; Tag = "FullscreenBorder2d"; Expect = "" }
    "compute"  = @{ Pkg = "$PkgBase.compute"; Act = ".ComputeActivity"; Tag = "ExampleCompute"; Expect = "1" }
    "texture"  = @{ Pkg = "$PkgBase.texture"; Act = ".TextureActivity"; Tag = "ExampleTexture"; Expect = "1" }
    "pointer"  = @{ Pkg = "$PkgBase.pointer"; Act = ".PointerActivity"; Tag = "ExamplePointer"; Expect = "1" }
    "cli"      = @{ Pkg = "$PkgBase.cli"; Act = ".CliActivity"; Tag = "ExampleCli"; Expect = "4" }
    "fs"       = @{ Pkg = "$PkgBase.fs"; Act = ".FsActivity"; Tag = "ExampleFs"; Expect = "4" }
    "tcp"      = @{ Pkg = "$PkgBase.tcp"; Act = ".TcpActivity"; Tag = "ExampleTcp"; Expect = "4" }
    "http-tcp" = @{ Pkg = "$PkgBase.httptcp"; Act = ".HttpTcpActivity"; Tag = "ExampleHttpTcp"; Expect = "4" }
}
if (-not $map.ContainsKey($Example)) { throw "unknown example: $Example" }
$e = $map[$Example]
$comp = "$($e.Pkg)/$PkgBase$($e.Act)"
adb logcat -c
adb shell am force-stop $e.Pkg 2>$null
adb shell am start -W -n $comp
Write-Host "started $comp (timeout ${TimeoutSec}s)"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    $dump = adb logcat -d
    $ok = $dump | Select-String "EXAMPLE_OK example=$Example" | Select-Object -Last 1
    if ($ok) {
        Write-Host $ok.Line
        if ($ok.Line -match "code=(\d+)") {
            $code = $Matches[1]
            if ($e.Expect -ne "" -and $code -ne $e.Expect) {
                throw "FAIL expected code=$($e.Expect) got code=$code"
            }
            Write-Host "PASS example=$Example code=$code"
            exit 0
        }
    }
    if ($dump | Select-String "EXAMPLE_FAIL example=$Example") {
        $dump | Select-String "EXAMPLE_FAIL example=$Example" | Select-Object -Last 5
        throw "FAIL example=$Example"
    }
    Start-Sleep -Seconds 1
}
throw "TIMEOUT example=$Example after ${TimeoutSec}s"
