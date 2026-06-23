param(
    [string]$Msys2Root = $env:MSYS2_ROOT,
    [ValidateSet('mingw32')]
    [string]$MsysEnvironment = 'mingw32',
    [string]$BuildDir = '',
    [string]$InstallDir = '',
    [int]$Jobs = 0,
    [switch]$RunBootstrap,
    [switch]$RunTopLevelBootstrap,
    [switch]$SkipConfigure,
    [switch]$SkipMake,
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common-WindowsRelease.ps1')

$repoRoot = Get-CiRepoRoot
if ([string]::IsNullOrWhiteSpace($Msys2Root)) {
    throw 'MSYS2 root is required. Pass -Msys2Root or set MSYS2_ROOT.'
}
if ($RunBootstrap -and $RunTopLevelBootstrap) {
    throw 'Specify only one bootstrap mode: -RunBootstrap or -RunTopLevelBootstrap.'
}

$msys2RootFull = Resolve-CiFullPath -Path $Msys2Root
$bashExe = Join-Path $msys2RootFull 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashExe)) {
    throw "MSYS2 bash.exe not found: $bashExe"
}

$mingwBinDir = Get-CiMingwBinDir -Msys2Root $msys2RootFull -MsysEnvironment $MsysEnvironment
$msystemName = switch ($MsysEnvironment) {
    'mingw32' { 'MINGW32' }
}
$hostTriplet = switch ($MsysEnvironment) {
    'mingw32' { 'i686-w64-mingw32' }
}
$compilerCommand = "$hostTriplet-gcc"
$compilerExe = Join-Path $mingwBinDir "$compilerCommand.exe"
if (-not (Test-Path -LiteralPath $compilerExe)) {
    throw "MSYS2 compiler not found: $compilerExe"
}

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
}

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $repoRoot 'build\ci-windows-x86-wchdriver'
}
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $repoRoot 'build\ci-install-windows-x86-wchdriver'
}

$buildDirFull = Resolve-CiFullPath -Path $BuildDir
$installDirFull = Resolve-CiFullPath -Path $InstallDir
Assert-CiPathInside -Path $buildDirFull -AllowedRoot $repoRoot -Purpose 'build output' | Out-Null
Assert-CiPathInside -Path $installDirFull -AllowedRoot $repoRoot -Purpose 'install output' | Out-Null

if (-not $SkipConfigure) {
    New-CiCleanDirectory -Path $buildDirFull -AllowedRoot $repoRoot | Out-Null
}
if (-not $SkipInstall) {
    New-CiCleanDirectory -Path $installDirFull -AllowedRoot $repoRoot | Out-Null
}

$repoPosix = ConvertTo-CiMsysPath -Path $repoRoot
$buildPosix = ConvertTo-CiMsysPath -Path $buildDirFull
$installPosix = ConvertTo-CiMsysPath -Path $installDirFull
$buildScriptPath = Join-Path $buildDirFull 'build-openocd-windows-x86-wchdriver.sh'
$buildScriptPosix = ConvertTo-CiMsysPath -Path $buildScriptPath

$configureFlags = @(
    '--host=i686-w64-mingw32',
    '--enable-wlinke',
    '--enable-wlinke-ch375-dll',
    '--disable-ch347',
    '--disable-linuxgpiod',
    '--disable-werror',
    '--disable-internal-libjaylink',
    '--disable-jlink',
    '--disable-doxygen-html',
    '--disable-doxygen-pdf',
    '--disable-capstone',
    '--disable-ftdi',
    '--disable-ftdi-cjtag',
    '--disable-stlink',
    '--disable-ti-icdi',
    '--disable-ulink',
    '--disable-usb-blaster-2',
    '--disable-ft232r',
    '--disable-vsllink',
    '--disable-xds110',
    '--disable-cmsis-dap-v2',
    '--disable-osbdm',
    '--disable-opendous',
    '--disable-armjtagew',
    '--disable-rlink',
    '--disable-usbprog',
    '--disable-aice',
    '--disable-cmsis-dap',
    '--disable-nulink',
    '--disable-kitprog',
    '--disable-usb-blaster',
    '--disable-presto',
    '--disable-openjtag',
    '--disable-xlnx-pcie-xvc',
    '--disable-buspirate',
    '--program-prefix='
)

$configureFlagLines = $configureFlags | ForEach-Object { "configure_flags+=('$_')" }
$runBootstrapValue = if ($RunBootstrap) { '1' } else { '0' }
$runTopLevelBootstrapValue = if ($RunTopLevelBootstrap) { '1' } else { '0' }
$skipConfigureValue = if ($SkipConfigure) { '1' } else { '0' }
$skipMakeValue = if ($SkipMake) { '1' } else { '0' }
$skipInstallValue = if ($SkipInstall) { '1' } else { '0' }

$buildScriptLines = @(
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '',
    'echo "MSYSTEM=${MSYSTEM:-}"',
    'echo "compiler: ${OPENOCD_CI_CC}"',
    'echo "repo: ${OPENOCD_CI_REPO}"',
    'echo "build: ${OPENOCD_CI_BUILD}"',
    'echo "install prefix: <staging-prefix>"',
    'echo "jobs: ${OPENOCD_CI_JOBS}"',
    '',
    'command -v "${OPENOCD_CI_CC}"',
    'command -v make',
    'command -v pkg-config || true',
    '',
    'mkdir -p "${OPENOCD_CI_BUILD}"',
    'cd "${OPENOCD_CI_BUILD}"',
    'echo "compiler sanity check"',
    '"${OPENOCD_CI_CC}" --version',
    'printf "int main(void){return 0;}\n" > conftest-ci-cc.c',
    '"${OPENOCD_CI_CC}" -c conftest-ci-cc.c -o conftest-ci-cc.o',
    'rm -f conftest-ci-cc.c conftest-ci-cc.o conftest-ci-cc.exe',
    '',
    'command -v make',
    'make --version | head -n 1',
    'pkg-config --version || true',
    '',
    'cd "${OPENOCD_CI_REPO}"',
    'if [ "${OPENOCD_CI_RUN_BOOTSTRAP}" = "1" ]; then',
    '  echo "running bootstrap"',
    '  sh ./bootstrap',
    'elif [ "${OPENOCD_CI_RUN_TOP_LEVEL_BOOTSTRAP}" = "1" ]; then',
    '  echo "running top-level autotools bootstrap"',
    '  aclocal --warnings=all',
    '  if command -v libtoolize >/dev/null 2>&1; then',
    '    libtoolize --automake --copy',
    '  elif command -v glibtoolize >/dev/null 2>&1; then',
    '    glibtoolize --automake --copy',
    '  else',
    '    echo "libtoolize is required" >&2',
    '    exit 1',
    '  fi',
    '  autoconf --warnings=all',
    '  autoheader --warnings=all',
    '  automake --warnings=all --gnu --add-missing --copy',
    '  if [ ! -x jimtcl/configure ]; then',
    '    echo "generating jimtcl configure wrapper"',
    '    cat > jimtcl/configure <<''JIMTCL_CONFIGURE_EOF''',
    '#!/bin/sh',
    'dir="`dirname "$0"`/autosetup"',
    'WRAPPER="$0"; export WRAPPER; exec "`"$dir/autosetup-find-tclsh"`" "$dir/autosetup" "$@"',
    'JIMTCL_CONFIGURE_EOF',
    '    chmod 755 jimtcl/configure',
    '  fi',
    'fi',
    '',
    'mkdir -p "${OPENOCD_CI_BUILD}"',
    'cd "${OPENOCD_CI_BUILD}"',
    '',
    'configure_flags=()'
)
$buildScriptLines += $configureFlagLines
$buildScriptLines += @(
    'prefix_arg="--prefix=${OPENOCD_CI_INSTALL}"',
    'configure_flags+=("${prefix_arg}")',
    '',
    'if [ "${OPENOCD_CI_SKIP_CONFIGURE}" != "1" ]; then',
    '  printf "configure argv:"',
    '  for arg in "${configure_flags[@]}"; do',
    '    printf " [%s]" "$arg"',
    '  done',
    '  printf "\n"',
    '  "${OPENOCD_CI_REPO}/configure" "${configure_flags[@]}"',
    'fi',
    '',
    'if [ "${OPENOCD_CI_SKIP_MAKE}" != "1" ]; then',
    '  make -j "${OPENOCD_CI_JOBS}"',
    'fi',
    '',
    'if [ "${OPENOCD_CI_SKIP_INSTALL}" != "1" ]; then',
    '  make install',
    'fi'
)

Write-CiTextFile -Path $buildScriptPath -Lines $buildScriptLines

$previousMsystem = $env:MSYSTEM
$previousChereInvoking = $env:CHERE_INVOKING
$previousPathType = $env:MSYS2_PATH_TYPE
$previousRepo = $env:OPENOCD_CI_REPO
$previousBuild = $env:OPENOCD_CI_BUILD
$previousInstall = $env:OPENOCD_CI_INSTALL
$previousJobs = $env:OPENOCD_CI_JOBS
$previousCc = $env:OPENOCD_CI_CC
$previousRunBootstrap = $env:OPENOCD_CI_RUN_BOOTSTRAP
$previousRunTopLevelBootstrap = $env:OPENOCD_CI_RUN_TOP_LEVEL_BOOTSTRAP
$previousSkipConfigure = $env:OPENOCD_CI_SKIP_CONFIGURE
$previousSkipMake = $env:OPENOCD_CI_SKIP_MAKE
$previousSkipInstall = $env:OPENOCD_CI_SKIP_INSTALL

try {
    $env:MSYSTEM = $msystemName
    $env:CHERE_INVOKING = '1'
    $env:MSYS2_PATH_TYPE = 'inherit'
    $env:OPENOCD_CI_REPO = $repoPosix
    $env:OPENOCD_CI_BUILD = $buildPosix
    $env:OPENOCD_CI_INSTALL = $installPosix
    $env:OPENOCD_CI_JOBS = [string]$Jobs
    $env:OPENOCD_CI_CC = $compilerCommand
    $env:OPENOCD_CI_RUN_BOOTSTRAP = $runBootstrapValue
    $env:OPENOCD_CI_RUN_TOP_LEVEL_BOOTSTRAP = $runTopLevelBootstrapValue
    $env:OPENOCD_CI_SKIP_CONFIGURE = $skipConfigureValue
    $env:OPENOCD_CI_SKIP_MAKE = $skipMakeValue
    $env:OPENOCD_CI_SKIP_INSTALL = $skipInstallValue

    $bashArgs = @(
        '--login',
        $buildScriptPosix
    )
    Invoke-CiCommand -FilePath $bashExe -Arguments $bashArgs
} finally {
    $env:MSYSTEM = $previousMsystem
    $env:CHERE_INVOKING = $previousChereInvoking
    $env:MSYS2_PATH_TYPE = $previousPathType
    $env:OPENOCD_CI_REPO = $previousRepo
    $env:OPENOCD_CI_BUILD = $previousBuild
    $env:OPENOCD_CI_INSTALL = $previousInstall
    $env:OPENOCD_CI_JOBS = $previousJobs
    $env:OPENOCD_CI_CC = $previousCc
    $env:OPENOCD_CI_RUN_BOOTSTRAP = $previousRunBootstrap
    $env:OPENOCD_CI_RUN_TOP_LEVEL_BOOTSTRAP = $previousRunTopLevelBootstrap
    $env:OPENOCD_CI_SKIP_CONFIGURE = $previousSkipConfigure
    $env:OPENOCD_CI_SKIP_MAKE = $previousSkipMake
    $env:OPENOCD_CI_SKIP_INSTALL = $previousSkipInstall
}

$installedExe = Join-Path $installDirFull 'bin\openocd.exe'
if (-not $SkipInstall) {
    if (-not (Test-Path -LiteralPath $installedExe)) {
        throw "Installed openocd.exe not found: $installedExe"
    }
    $exeHash = Get-CiFileSha256 -Path $installedExe
    $exeSize = Get-CiFileSize -Path $installedExe
    Write-Host "built openocd.exe: $installedExe"
    Write-Host "openocd.exe sha256: $exeHash"
    Write-Host "openocd.exe size: $exeSize"
}

Write-Host "Build directory: $buildDirFull"
Write-Host "Install directory: $installDirFull"
