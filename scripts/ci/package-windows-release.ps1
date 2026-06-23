param(
    [Parameter(Mandatory = $true)]
    [string]$PackageVersion,
    [string]$ReleaseTag = '',
    [string]$InstallDir = '',
    [string]$OpenOcdExe = '',
    [string]$ScriptsDir = '',
    [string]$DistDir = '',
    [string]$ArchiveSuffix = 'windows-x86',
    [string]$SourceRepoUrl = '',
    [string]$SourceCommit = '',
    [string]$Msys2Root = $env:MSYS2_ROOT,
    [ValidateSet('mingw32')]
    [string]$MsysEnvironment = 'mingw32',
    [string]$ObjdumpExe = '',
    [string[]]$RuntimeDllSearchDirs = @(),
    [string]$PrivateDenylistPath = '',
    [switch]$SkipSmokeTest,
    [switch]$SkipTextAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common-WindowsRelease.ps1')

function Copy-DirectoryContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source directory not found: $Source"
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Assert-ReleaseExeSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExePath
    )

    $normalizedPath = (Resolve-CiFullPath -Path $ExePath).ToLowerInvariant()
    $forbiddenFragments = @(
        '\upstreams\openwch-openocd_wch\bin\openocd.exe',
        '\openwch\openocd_wch\bin\openocd.exe'
    )
    foreach ($fragment in $forbiddenFragments) {
        if ($normalizedPath.Contains($fragment)) {
            throw "Refusing to package official binary: $ExePath"
        }
    }
}

$repoRoot = Get-CiRepoRoot
if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $ReleaseTag = "v$PackageVersion"
}
if ([string]::IsNullOrWhiteSpace($DistDir)) {
    $DistDir = Join-Path $repoRoot 'dist'
}
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $repoRoot 'build\ci-install-windows-x86-wchdriver'
}

$installDirFull = Resolve-CiFullPath -Path $InstallDir
if ([string]::IsNullOrWhiteSpace($OpenOcdExe)) {
    $OpenOcdExe = Join-Path $installDirFull 'bin\openocd.exe'
}
if ([string]::IsNullOrWhiteSpace($ScriptsDir)) {
    $ScriptsDir = Join-Path $installDirFull 'share\openocd\scripts'
}
if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
    $commitArgs = @(
        'rev-parse',
        'HEAD'
    )
    $SourceCommit = Get-CiGitValue -Arguments $commitArgs -RepoRoot $repoRoot
}
if ([string]::IsNullOrWhiteSpace($SourceRepoUrl)) {
    $urlArgs = @(
        'config',
        '--get',
        'remote.origin.url'
    )
    $SourceRepoUrl = Get-CiGitValue -Arguments $urlArgs -RepoRoot $repoRoot
}
if ([string]::IsNullOrWhiteSpace($SourceRepoUrl)) {
    $SourceRepoUrl = '<not set>'
}
if ($SourceRepoUrl -match '^[A-Za-z]:[\\/]|^/|Users[\\/]') {
    throw 'SourceRepoUrl appears to be a local path. Pass a public source URL explicitly.'
}

$openOcdExeFull = Resolve-CiFullPath -Path $OpenOcdExe
$scriptsDirFull = Resolve-CiFullPath -Path $ScriptsDir
if (-not (Test-Path -LiteralPath $openOcdExeFull)) {
    throw "openocd.exe not found: $openOcdExeFull"
}
if (-not (Test-Path -LiteralPath $scriptsDirFull)) {
    throw "OpenOCD scripts directory not found: $scriptsDirFull"
}
Assert-ReleaseExeSource -ExePath $openOcdExeFull

$distDirFull = Resolve-CiFullPath -Path $DistDir
Assert-CiPathInside -Path $distDirFull -AllowedRoot $repoRoot -Purpose 'dist output' | Out-Null
if (-not (Test-Path -LiteralPath $distDirFull)) {
    New-Item -ItemType Directory -Path $distDirFull | Out-Null
}

$rootName = "openocd-wch-ch32v003-bootfix-$PackageVersion-$ArchiveSuffix"
$stageDir = Join-Path $distDirFull $rootName
$archivePath = Join-Path $distDirFull "$rootName.zip"
$stageDirFull = New-CiCleanDirectory -Path $stageDir -AllowedRoot $repoRoot
if (Test-Path -LiteralPath $archivePath) {
    $archiveFull = Assert-CiPathInside -Path $archivePath -AllowedRoot $repoRoot -Purpose 'archive replacement'
    Write-Host "Remove target: $archiveFull"
    Remove-Item -LiteralPath $archiveFull -Force -ErrorAction Stop
}

$stageBinDir = Join-Path $stageDirFull 'bin'
$stageShareScriptsDir = Join-Path $stageDirFull 'share\openocd\scripts'
$stageCompatScriptsDir = Join-Path $stageDirFull 'scripts'
New-Item -ItemType Directory -Path $stageBinDir | Out-Null
New-Item -ItemType Directory -Path $stageShareScriptsDir | Out-Null
New-Item -ItemType Directory -Path $stageCompatScriptsDir | Out-Null

$stageOpenOcdExe = Join-Path $stageBinDir 'openocd.exe'
Copy-Item -LiteralPath $openOcdExeFull -Destination $stageOpenOcdExe -Force
Copy-DirectoryContent -Source $scriptsDirFull -Destination $stageShareScriptsDir
Copy-DirectoryContent -Source $scriptsDirFull -Destination $stageCompatScriptsDir

$copyPairs = @(
    @{ Source = (Join-Path $repoRoot 'COPYING'); Destination = (Join-Path $stageDirFull 'COPYING') },
    @{ Source = (Join-Path $repoRoot 'README.md'); Destination = (Join-Path $stageDirFull 'README.md') },
    @{ Source = (Join-Path $repoRoot 'docs\license-and-release-policy.md'); Destination = (Join-Path $stageDirFull 'LICENSE-AND-RELEASE-POLICY.md') }
)
foreach ($pair in $copyPairs) {
    if (-not (Test-Path -LiteralPath $pair.Source)) {
        throw "Required package file not found: $($pair.Source)"
    }
    Copy-Item -LiteralPath $pair.Source -Destination $pair.Destination -Force
}

$licensesSource = Join-Path $repoRoot 'LICENSES'
$licensesDestination = Join-Path $stageDirFull 'LICENSES'
if (-not (Test-Path -LiteralPath $licensesSource)) {
    throw "LICENSES directory not found: $licensesSource"
}
Copy-Item -LiteralPath $licensesSource -Destination $licensesDestination -Recurse -Force

$objdumpFull = Resolve-CiObjdump -ObjdumpExe $ObjdumpExe -Msys2Root $Msys2Root -MsysEnvironment $MsysEnvironment
$importedDlls = Get-CiImportedDllNames -OpenOcdExe $stageOpenOcdExe -ObjdumpExe $objdumpFull
Assert-CiNoForbiddenDllNames -DllNames $importedDlls

$dllImportLines = @(
    'OpenOCD Windows DLL import audit',
    '================================',
    '',
    "Package version: $PackageVersion",
    "Source commit: $SourceCommit",
    '',
    'Imported DLLs:',
    (($importedDlls | Sort-Object -Unique | ForEach-Object { "- $_" }) -join [Environment]::NewLine),
    '',
    'Forbidden DLL audit:',
    '- passed',
    '',
    'Forbidden DLL names:',
    '- WCHLinkDLL.dll',
    '- CH347DLL.dll',
    '- JLinkARM.dll',
    '- FTD2XX.dll'
)
Write-CiTextFile -Path (Join-Path $stageDirFull 'DLL-IMPORTS.txt') -Lines $dllImportLines

$runtimeSearchDirs = New-Object System.Collections.Generic.List[string]
foreach ($dir in $RuntimeDllSearchDirs) {
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        $runtimeSearchDirs.Add((Resolve-CiFullPath -Path $dir))
    }
}
if (-not [string]::IsNullOrWhiteSpace($Msys2Root)) {
    $mingwBinDir = Get-CiMingwBinDir -Msys2Root $Msys2Root -MsysEnvironment $MsysEnvironment
    $runtimeSearchDirs.Add($mingwBinDir)
}

$nonSystemDlls = Get-CiNonSystemDllNames -DllNames $importedDlls
$bundledRuntimeDlls = New-Object System.Collections.Generic.List[string]
foreach ($dllName in $nonSystemDlls) {
    $runtimeDll = Find-CiRuntimeDll -DllName $dllName -SearchDirs $runtimeSearchDirs
    if ([string]::IsNullOrWhiteSpace($runtimeDll)) {
        throw "Non-system DLL import could not be staged: $dllName"
    }
    $destinationDll = Join-Path $stageBinDir $dllName
    Copy-Item -LiteralPath $runtimeDll -Destination $destinationDll -Force
    $bundledRuntimeDlls.Add($dllName)
}

$versionArgs = @(
    '-s',
    (Join-Path $stageDirFull 'share\openocd\scripts'),
    '-c',
    'version',
    '-c',
    'shutdown'
)
$openOcdVersionOutput = Invoke-CiCommandCapture -FilePath $stageOpenOcdExe -Arguments $versionArgs
$openOcdVersionLine = ($openOcdVersionOutput | Where-Object { $_ -match 'Open On-Chip Debugger' } | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($openOcdVersionLine)) {
    $openOcdVersionLine = ($openOcdVersionOutput | Select-Object -First 1)
}

$exeHash = Get-CiFileSha256 -Path $stageOpenOcdExe
$exeSize = Get-CiFileSize -Path $stageOpenOcdExe
$configureSummary = '--host=i686-w64-mingw32 --enable-wlinke --enable-wlinke-ch375-dll --disable-ch347 --disable-linuxgpiod --disable-werror --program-prefix='

$sourceLines = @(
    'OpenOCD WCH CH32V003 BOOT write fix source',
    '===========================================',
    '',
    "Package version: $PackageVersion",
    "Release tag: $ReleaseTag",
    "Source repo: $SourceRepoUrl",
    "Source commit: $SourceCommit",
    '',
    'Source base:',
    '- WCH OpenOCD source mirror used as the hard-fork base',
    '- Local CH32V003 BOOT/system flash write fixes in this repository',
    '',
    'Release rule:',
    '- The archive does not redistribute openwch/openocd_wch/bin/openocd.exe.',
    '- The archive is built for windows-x86 / i686-mingw32 / WCHLinkDLL backend.',
    '- WCHLinkDLL.dll and CH347DLL.dll are not bundled.'
)
Write-CiTextFile -Path (Join-Path $stageDirFull 'SOURCE.txt') -Lines $sourceLines

$noticeTemplate = Join-Path $repoRoot 'packaging\windows\NOTICE.template.txt'
if (-not (Test-Path -LiteralPath $noticeTemplate)) {
    throw "NOTICE template not found: $noticeTemplate"
}
$runtimeListText = '<none>'
if ($bundledRuntimeDlls.Count -gt 0) {
    $runtimeListText = (($bundledRuntimeDlls | Sort-Object -Unique | ForEach-Object { "- $_" }) -join [Environment]::NewLine)
}
$noticeText = Get-Content -LiteralPath $noticeTemplate -Raw
$noticeText = $noticeText.Replace('<version>', $PackageVersion)
$noticeText = $noticeText.Replace('<commit>', $SourceCommit)
$noticeText = $noticeText.Replace('<tag>', $ReleaseTag)
$noticeText = $noticeText.Replace('- <list bundled runtime DLLs, if any>', $runtimeListText)
Set-Content -LiteralPath (Join-Path $stageDirFull 'NOTICE.txt') -Value $noticeText -Encoding ASCII

$buildInfoLines = @(
    'OpenOCD WCH Windows build information',
    '======================================',
    '',
    "Package version: $PackageVersion",
    "Release tag: $ReleaseTag",
    "Source repo: $SourceRepoUrl",
    "Source commit: $SourceCommit",
    'Package label: windows-x86',
    'Arduino host: i686-mingw32',
    'Backend: WCHLinkDLL',
    'Driver stack: WCH official driver stack installed outside this archive',
    "Configure options: $configureSummary",
    "OpenOCD version: $openOcdVersionLine",
    "openocd.exe SHA256: $exeHash",
    "openocd.exe size: $exeSize",
    '',
    'Imported DLLs:',
    (($importedDlls | ForEach-Object { "- $_" }) -join [Environment]::NewLine),
    '',
    'Bundled runtime DLLs:',
    $runtimeListText,
    '',
    'Not bundled:',
    '- WCHLinkDLL.dll',
    '- CH347DLL.dll',
    '- JLinkARM.dll',
    '- FTD2XX.dll'
)
Write-CiTextFile -Path (Join-Path $stageDirFull 'BUILDINFO.txt') -Lines $buildInfoLines

$requiredDocs = @(
    'COPYING',
    'LICENSES',
    'NOTICE.txt',
    'SOURCE.txt',
    'BUILDINFO.txt',
    'DLL-IMPORTS.txt',
    'LICENSE-AND-RELEASE-POLICY.md'
)
foreach ($requiredDoc in $requiredDocs) {
    $requiredPath = Join-Path $stageDirFull $requiredDoc
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required release document missing: $requiredDoc"
    }
}

if (-not $SkipSmokeTest) {
    $smokeScript = Join-Path $PSScriptRoot 'smoke-windows-release.ps1'
    $smokeArgs = @(
        '-StageDir',
        $stageDirFull
    )
    $powerShellArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $smokeScript
    )
    $powerShellArgs += $smokeArgs
    Invoke-CiCommand -FilePath 'powershell' -Arguments $powerShellArgs
}

if (-not $SkipTextAudit) {
    $auditScript = Join-Path $PSScriptRoot 'audit-release-text.ps1'
    $auditArgs = @(
        '-StageDir',
        $stageDirFull,
        '-ObjdumpExe',
        $objdumpFull
    )
    if (-not [string]::IsNullOrWhiteSpace($PrivateDenylistPath)) {
        $auditArgs += @(
            '-PrivateDenylistPath',
            $PrivateDenylistPath
        )
    }
    $powerShellArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $auditScript
    )
    $powerShellArgs += $auditArgs
    Invoke-CiCommand -FilePath 'powershell' -Arguments $powerShellArgs
}

$shaLines = New-Object System.Collections.Generic.List[string]
$filesForHash = Get-ChildItem -LiteralPath $stageDirFull -Recurse -File |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
    Sort-Object FullName
foreach ($file in $filesForHash) {
    $relativePath = (Get-CiRelativePath -BaseDir $stageDirFull -Path $file.FullName).Replace('\', '/')
    $fileHash = Get-CiFileSha256 -Path $file.FullName
    $shaLines.Add("$fileHash  $relativePath")
}
Write-CiTextFile -Path (Join-Path $stageDirFull 'SHA256SUMS.txt') -Lines @($shaLines)

Compress-Archive -LiteralPath $stageDirFull -DestinationPath $archivePath -Force

$archiveHash = Get-CiFileSha256 -Path $archivePath
$archiveSize = Get-CiFileSize -Path $archivePath
$archiveName = Split-Path -Leaf $archivePath
$sidecarPath = "$archivePath.sha256.txt"
$sidecarLines = @(
    "$archiveHash  $archiveName"
)
Write-CiTextFile -Path $sidecarPath -Lines $sidecarLines

Write-Host "archive: $archivePath"
Write-Host "archive SHA256: $archiveHash"
Write-Host "archive size: $archiveSize"
Write-Host "stage dir: $stageDirFull"
