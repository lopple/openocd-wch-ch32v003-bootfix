Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CiRepoRoot {
    $scriptDir = Split-Path -Parent $PSScriptRoot
    return (Split-Path -Parent $scriptDir)
}

function Resolve-CiFullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$BaseDir = (Get-Location).Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $combinedPath = Join-Path $BaseDir $Path
    return [System.IO.Path]::GetFullPath($combinedPath)
}

function Assert-CiPathInside {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot,
        [string]$Purpose = 'operation'
    )

    $fullPath = Resolve-CiFullPath -Path $Path
    $fullRoot = Resolve-CiFullPath -Path $AllowedRoot
    $rootWithSeparator = $fullRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    $isRoot = [string]::Equals($fullPath, $fullRoot, [StringComparison]::OrdinalIgnoreCase)
    $isChild = $fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)
    if (-not ($isRoot -or $isChild)) {
        throw "Refusing $Purpose outside allowed root: $fullPath"
    }

    return $fullPath
}

function New-CiCleanDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    $fullPath = Assert-CiPathInside -Path $Path -AllowedRoot $AllowedRoot -Purpose 'directory cleanup'
    if (Test-Path -LiteralPath $fullPath) {
        Write-Host "Remove target: $fullPath"
        Get-ChildItem -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $_.Attributes = [System.IO.FileAttributes]::Normal
            } catch {
            }
        }

        $removed = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop
                $removed = $true
                break
            } catch {
                if ($attempt -eq 3) {
                    throw
                }
                Start-Sleep -Seconds 2
            }
        }

        if (-not $removed) {
            throw "Failed to remove target: $fullPath"
        }
    }

    New-Item -ItemType Directory -Path $fullPath | Out-Null
    return $fullPath
}

function Format-CiArgv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $formattedArgs = ($Arguments | ForEach-Object { '[' + $_ + ']' }) -join ' '
    return "argv: [$FilePath] $formattedArgs"
}

function Invoke-CiCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ''
    )

    Write-Host (Format-CiArgv -FilePath $FilePath -Arguments $Arguments)
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        & $FilePath @Arguments
    } else {
        Push-Location -LiteralPath $WorkingDirectory
        try {
            & $FilePath @Arguments
        } finally {
            Pop-Location
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath"
    }
}

function Invoke-CiCommandCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ''
    )

    Write-Host (Format-CiArgv -FilePath $FilePath -Arguments $Arguments)
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $output = & $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        } else {
            Push-Location -LiteralPath $WorkingDirectory
            try {
                $output = & $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() }
            } finally {
                Pop-Location
            }
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        $joinedOutput = ($output -join [Environment]::NewLine)
        throw "Command failed with exit code $exitCode`: $FilePath`n$joinedOutput"
    }

    return @($output)
}

function ConvertTo-CiMsysPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = Resolve-CiFullPath -Path $Path
    if ($fullPath -match '^[A-Za-z]:') {
        $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
        $rest = $fullPath.Substring(2).TrimStart('\').Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($rest)) {
            return "/$drive"
        }
        return "/$drive/$rest"
    }

    throw "Unsupported path form for MSYS conversion: $fullPath"
}

function Get-CiGitValue {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$RepoRoot = (Get-CiRepoRoot)
    )

    try {
        $output = Invoke-CiCommandCapture -FilePath 'git' -Arguments $Arguments -WorkingDirectory $RepoRoot
        return (($output | Select-Object -First 1) -as [string])
    } catch {
        return ''
    }
}

function Get-CiFileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
    return $hash.Hash.ToUpperInvariant()
}

function Get-CiFileSize {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path
    return $item.Length
}

function Get-CiRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseDir,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $baseFull = (Resolve-CiFullPath -Path $BaseDir).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $pathFull = Resolve-CiFullPath -Path $Path
    $baseUri = New-Object System.Uri($baseFull)
    $pathUri = New-Object System.Uri($pathFull)
    $relativeUri = $baseUri.MakeRelativeUri($pathUri)
    return ([System.Uri]::UnescapeDataString($relativeUri.ToString())).Replace('/', '\')
}

function Get-CiMingwBinDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Msys2Root,
        [ValidateSet('mingw32', 'mingw64', 'ucrt64', 'clang64')]
        [string]$MsysEnvironment = 'mingw32'
    )

    $binDir = Join-Path $Msys2Root "$MsysEnvironment\bin"
    if (-not (Test-Path -LiteralPath $binDir)) {
        throw "MSYS2 MinGW bin directory not found: $binDir"
    }
    return (Resolve-CiFullPath -Path $binDir)
}

function Resolve-CiObjdump {
    param(
        [string]$ObjdumpExe = '',
        [string]$Msys2Root = '',
        [ValidateSet('mingw32', 'mingw64', 'ucrt64', 'clang64')]
        [string]$MsysEnvironment = 'mingw32'
    )

    if (-not [string]::IsNullOrWhiteSpace($ObjdumpExe)) {
        $resolvedObjdump = Resolve-CiFullPath -Path $ObjdumpExe
        if (-not (Test-Path -LiteralPath $resolvedObjdump)) {
            throw "objdump.exe not found: $resolvedObjdump"
        }
        return $resolvedObjdump
    }

    if (-not [string]::IsNullOrWhiteSpace($Msys2Root)) {
        $mingwBinDir = Get-CiMingwBinDir -Msys2Root $Msys2Root -MsysEnvironment $MsysEnvironment
        $candidate = Join-Path $mingwBinDir 'objdump.exe'
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-CiFullPath -Path $candidate)
        }
    }

    $command = Get-Command 'objdump.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw 'objdump.exe not found. Pass -ObjdumpExe or -Msys2Root.'
}

function Get-CiImportedDllNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OpenOcdExe,
        [Parameter(Mandatory = $true)]
        [string]$ObjdumpExe
    )

    $objdumpArgs = @(
        '-p',
        $OpenOcdExe
    )
    $output = Invoke-CiCommandCapture -FilePath $ObjdumpExe -Arguments $objdumpArgs
    $dllNames = New-Object System.Collections.Generic.List[string]
    foreach ($line in $output) {
        if ($line -match '^\s*DLL Name:\s*(.+?)\s*$') {
            $dllNames.Add($Matches[1])
        }
    }

    return @($dllNames | Sort-Object -Unique)
}

function Get-CiForbiddenDllNames {
    return @(
        'WCHLinkDLL.dll',
        'CH347DLL.dll',
        'JLinkARM.dll',
        'FTD2XX.dll'
    )
}

function Get-CiWindowsSystemDllNames {
    return @(
        'ADVAPI32.dll',
        'COMCTL32.dll',
        'COMDLG32.dll',
        'GDI32.dll',
        'IMM32.dll',
        'KERNEL32.dll',
        'msvcrt.dll',
        'OLE32.dll',
        'OLEAUT32.dll',
        'SHELL32.dll',
        'USER32.dll',
        'VERSION.dll',
        'WINMM.dll',
        'WINSPOOL.DRV',
        'WS2_32.dll'
    )
}

function Assert-CiNoForbiddenDllNames {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DllNames,
        [string[]]$AdditionalForbiddenDllNames = @()
    )

    $forbidden = @((Get-CiForbiddenDllNames) + $AdditionalForbiddenDllNames)
    $forbiddenLower = $forbidden | ForEach-Object { $_.ToLowerInvariant() }
    foreach ($dllName in $DllNames) {
        if ($forbiddenLower -contains $dllName.ToLowerInvariant()) {
            throw "Forbidden DLL dependency or bundled DLL found: $dllName"
        }
    }
}

function Get-CiNonSystemDllNames {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DllNames
    )

    $systemLower = (Get-CiWindowsSystemDllNames) | ForEach-Object { $_.ToLowerInvariant() }
    return @($DllNames | Where-Object { $systemLower -notcontains $_.ToLowerInvariant() })
}

function Find-CiRuntimeDll {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DllName,
        [string[]]$SearchDirs = @()
    )

    foreach ($searchDir in $SearchDirs) {
        if ([string]::IsNullOrWhiteSpace($searchDir)) {
            continue
        }
        $candidate = Join-Path $searchDir $DllName
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-CiFullPath -Path $candidate)
        }
    }

    return ''
}

function Write-CiTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    Set-Content -LiteralPath $Path -Value $Lines -Encoding ASCII
}
