param(
    [Parameter(Mandatory = $true)]
    [string]$StageDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common-WindowsRelease.ps1')

$stageDirFull = Resolve-CiFullPath -Path $StageDir
$openOcdExe = Join-Path $stageDirFull 'bin\openocd.exe'
$scriptsDir = Join-Path $stageDirFull 'share\openocd\scripts'

if (-not (Test-Path -LiteralPath $openOcdExe)) {
    throw "openocd.exe not found in stage: $openOcdExe"
}
if (-not (Test-Path -LiteralPath $scriptsDir)) {
    throw "scripts directory not found in stage: $scriptsDir"
}

$binDir = Split-Path -Parent $openOcdExe
$previousPath = $env:Path
try {
    $env:Path = $binDir + [System.IO.Path]::PathSeparator + $previousPath

    $versionArgs = @(
        '-s',
        $scriptsDir,
        '-c',
        'version',
        '-c',
        'shutdown'
    )
    Invoke-CiCommand -FilePath $openOcdExe -Arguments $versionArgs

    $ch32v003Args = @(
        '-s',
        $scriptsDir,
        '-f',
        'target/wch-riscv-ch32v003.cfg',
        '-c',
        'shutdown'
    )
    Invoke-CiCommand -FilePath $openOcdExe -Arguments $ch32v003Args

    $genericArgs = @(
        '-s',
        $scriptsDir,
        '-f',
        'target/wch-riscv.cfg',
        '-c',
        'chip_id CH641',
        '-c',
        'shutdown'
    )
    Invoke-CiCommand -FilePath $openOcdExe -Arguments $genericArgs
} finally {
    $env:Path = $previousPath
}

Write-Host "Targetless smoke test passed: $stageDirFull"
