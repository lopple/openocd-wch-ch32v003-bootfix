param(
    [Parameter(Mandatory = $true)]
    [string]$StageDir,
    [string]$PrivateDenylistPath = '',
    [string]$ObjdumpExe = '',
    [string]$Msys2Root = $env:MSYS2_ROOT,
    [ValidateSet('mingw32')]
    [string]$MsysEnvironment = 'mingw32',
    [string[]]$AdditionalForbiddenDllNames = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common-WindowsRelease.ps1')

$stageDirFull = Resolve-CiFullPath -Path $StageDir
if (-not (Test-Path -LiteralPath $stageDirFull)) {
    throw "Stage directory not found: $stageDirFull"
}

$requiredPaths = @(
    'bin/openocd.exe',
    'share/openocd/scripts',
    'scripts',
    'COPYING',
    'LICENSES',
    'NOTICE.txt',
    'SOURCE.txt',
    'BUILDINFO.txt',
    'LICENSE-AND-RELEASE-POLICY.md'
)
foreach ($relativePath in $requiredPaths) {
    $requiredPath = Join-Path $stageDirFull $relativePath
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required staged path missing: $relativePath"
    }
}

$forbiddenBundledDlls = @((Get-CiForbiddenDllNames) + $AdditionalForbiddenDllNames)
$bundledDlls = Get-ChildItem -LiteralPath $stageDirFull -Recurse -File -Filter '*.dll'
foreach ($dll in $bundledDlls) {
    $dllName = $dll.Name
    $forbiddenLower = $forbiddenBundledDlls | ForEach-Object { $_.ToLowerInvariant() }
    if ($forbiddenLower -contains $dllName.ToLowerInvariant()) {
        throw "Forbidden DLL bundled in release stage: $($dll.FullName)"
    }
}

$openOcdExe = Join-Path $stageDirFull 'bin\openocd.exe'
$objdumpFull = Resolve-CiObjdump -ObjdumpExe $ObjdumpExe -Msys2Root $Msys2Root -MsysEnvironment $MsysEnvironment
$importedDlls = Get-CiImportedDllNames -OpenOcdExe $openOcdExe -ObjdumpExe $objdumpFull
Assert-CiNoForbiddenDllNames -DllNames $importedDlls -AdditionalForbiddenDllNames $AdditionalForbiddenDllNames

$importsPath = Join-Path $stageDirFull 'DLL-IMPORTS.txt'
$importLines = @(
    'Imported DLLs from bin/openocd.exe',
    '==================================',
    ''
)
$importLines += ($importedDlls | ForEach-Object { "- $_" })
Write-CiTextFile -Path $importsPath -Lines $importLines

$pathPatterns = @(
    '(?<![A-Za-z])[A-Za-z]:[\\/]',
    'Users[\\/]',
    '(^|[\s=:"''])/[a-z]/[A-Za-z0-9._-]+'
)
$textFiles = Get-ChildItem -LiteralPath $stageDirFull -Recurse -File |
    Where-Object { $_.Extension -in @('.txt', '.md') }
foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $pathPatterns) {
        if ($content -match $pattern) {
            $relativePath = (Get-CiRelativePath -BaseDir $stageDirFull -Path $file.FullName).Replace('\', '/')
            throw "Release text contains a local path pattern [$pattern]: $relativePath"
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($PrivateDenylistPath)) {
    $denylistFull = Resolve-CiFullPath -Path $PrivateDenylistPath
    if (-not (Test-Path -LiteralPath $denylistFull)) {
        throw "Private denylist not found: $denylistFull"
    }
    $denyPatterns = Get-Content -LiteralPath $denylistFull |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Where-Object { -not $_.TrimStart().StartsWith('#') }
    foreach ($file in $textFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($denyPattern in $denyPatterns) {
            if ($content -match [regex]::Escape($denyPattern)) {
                $relativePath = (Get-CiRelativePath -BaseDir $stageDirFull -Path $file.FullName).Replace('\', '/')
                throw "Release text contains a private denylist entry in: $relativePath"
            }
        }
    }
}

Write-Host "Release text/import audit passed: $stageDirFull"
