param(
    [string]$OpenOcdExe = ".\upstreams\openwch-openocd_wch\bin\openocd.exe",
    [string]$Config = ".\upstreams\openwch-openocd_wch\bin\wch-riscv.cfg",
    [string]$BootloaderBin = "",
    [string]$ExpectedBootloaderSha256 = "",
    [string]$EvidenceDir = "",
    [string[]]$RuntimePath = @(),
    [int]$UserSize = 0x4000,
    [int]$UserHeadSize = 0x1000,
    [int]$BootSize = 0x1000,
    [switch]$UseBankCommands,
    [switch]$ExecuteReadOnly,
    [switch]$PlanWrite,
    [switch]$ExecuteWritePlanTrap,
    [switch]$ExecuteWrite,
    [switch]$ConfirmWriteToBoot
)

$ErrorActionPreference = "Stop"

function Format-Argv {
    param([string[]]$Argv)
    return (($Argv | ForEach-Object { "[" + $_ + "]" }) -join " ")
}

function Resolve-RuntimePath {
    param([string[]]$Paths)

    $resolvedPaths = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $resolvedPath = (Resolve-Path -LiteralPath $path).Path
        $resolvedPaths += $resolvedPath
    }

    return $resolvedPaths
}

function Invoke-LoggedOpenOcd {
    param(
        [string]$Exe,
        [string[]]$Argv,
        [string[]]$RuntimePath,
        [string]$LogPath,
        [switch]$Execute
    )

    $formattedArgs = Format-Argv -Argv $Argv
    Write-Host "exe: [$Exe]"
    Write-Host "argv: $formattedArgs"
    if ($RuntimePath.Count -gt 0) {
        $formattedRuntimePath = Format-Argv -Argv $RuntimePath
        Write-Host "runtime path: $formattedRuntimePath"
    }
    Write-Host "log: [$LogPath]"

    if (-not $Execute) {
        Write-Host "dry-run: command not executed"
        return
    }

    $originalPath = $env:Path
    try {
        if ($RuntimePath.Count -gt 0) {
            $runtimePrefix = $RuntimePath -join [System.IO.Path]::PathSeparator
            $env:Path = $runtimePrefix + [System.IO.Path]::PathSeparator + $originalPath
        }

        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $openOcdOutput = @(& $Exe @Argv 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        $openOcdText = @($openOcdOutput | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            } else {
                $_.ToString()
            }
        })
        $openOcdText | Tee-Object -FilePath $LogPath

        $errorLineCount = @($openOcdText | Where-Object { $_ -match "\bError:" }).Count
        $statusLine = "openocd exit code: [$exitCode], error lines: [$errorLineCount]"
        $statusLine | Tee-Object -FilePath $LogPath -Append

        if (($exitCode -ne 0) -or ($errorLineCount -gt 0)) {
            throw $statusLine
        }
    } finally {
        $env:Path = $originalPath
    }
}

function Convert-ToTclPath {
    param([string]$Path)
    $resolvedPath = Resolve-Path -LiteralPath $Path
    return ($resolvedPath.Path -replace "\\", "/")
}

function Convert-FromTclPath {
    param([string]$Path)
    return ($Path -replace "/", "\")
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Test-BinaryPrefix {
    param(
        [string]$ExpectedPath,
        [string]$ActualPath
    )

    $expectedBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ExpectedPath).Path)
    $actualBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ActualPath).Path)

    if ($actualBytes.Length -lt $expectedBytes.Length) {
        throw "actual file is shorter than expected prefix: actual=[$($actualBytes.Length)] expected=[$($expectedBytes.Length)]"
    }

    for ($i = 0; $i -lt $expectedBytes.Length; $i++) {
        if ($expectedBytes[$i] -ne $actualBytes[$i]) {
            $offset = "0x{0:x}" -f $i
            throw "binary prefix mismatch at offset [$offset]"
        }
    }
}

function Assert-WritePlanTrapLog {
    param(
        [string]$LogPath,
        [int]$BootloaderSize
    )

    $text = Get-Content -LiteralPath $LogPath -Raw
    $lowerText = $text.ToLowerInvariant()
    if (-not $lowerText.Contains("wlink_write plan:")) {
        throw "write plan trap log does not contain final wlink_write plan."
    }
    if (-not $lowerText.Contains("wch-link write plan trap: refusing to execute flash transfer")) {
        throw "write plan trap log does not contain the expected trap refusal."
    }
    if ($lowerText.Contains("wlink_ready_write")) {
        throw "write plan trap failed: wlink_ready_write was reached."
    }
    if ($lowerText.Contains("wlink_fastprogram")) {
        throw "write plan trap failed: wlink_fastprogram was reached."
    }

    $expectedCount = "0x{0:x8}" -f $BootloaderSize
    $expectedPadded = [int]([Math]::Ceiling($BootloaderSize / 64.0) * 64)
    $expectedPaddedText = "0x{0:x8}" -f $expectedPadded
    $expectedEnd = [uint64]0x1ffff000 + [uint64]$expectedPadded - 1
    $expectedEndText = "0x{0:x8}" -f $expectedEnd

    if (-not $lowerText.Contains("address=0x1ffff000")) {
        throw "write plan trap log does not target BOOT address 0x1ffff000."
    }
    if (-not $lowerText.Contains("count=$expectedCount")) {
        throw "write plan trap log count mismatch: expected [$expectedCount]."
    }
    if (-not $lowerText.Contains("alignment=64")) {
        throw "write plan trap log does not use 64-byte alignment."
    }
    if (-not $lowerText.Contains("padded=$expectedPaddedText")) {
        throw "write plan trap log padded size mismatch: expected [$expectedPaddedText]."
    }
    if (-not $lowerText.Contains("end=$expectedEndText")) {
        throw "write plan trap log end address mismatch: expected [$expectedEndText]."
    }
    if (-not $lowerText.Contains("ch32v003_boot=1")) {
        throw "write plan trap log did not classify the write as CH32V003 BOOT."
    }
}

function Assert-BootloaderInput {
    param(
        [string]$Path,
        [int]$MaxSize,
        [string]$ExpectedSha256,
        [switch]$RequireExpectedSha256
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "BootloaderBin is required for -PlanWrite, -ExecuteWritePlanTrap or -ExecuteWrite."
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        throw "BootloaderBin is empty: $($item.FullName)"
    }

    if ($item.Length -gt $MaxSize) {
        $maxSizeHex = "0x{0:x}" -f $MaxSize
        throw "BootloaderBin is larger than BOOT flash: size=[$($item.Length)] max=[$maxSizeHex] path=[$($item.FullName)]"
    }

    $actualSha256 = Get-Sha256 -Path $item.FullName
    Write-Host "BOOTLOADER path: [$($item.FullName)]"
    Write-Host "BOOTLOADER size: [$($item.Length)]"
    Write-Host "BOOTLOADER sha256: [$actualSha256]"

    if ($RequireExpectedSha256 -and [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        throw "ExpectedBootloaderSha256 is required with -ExecuteWrite."
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        $normalizedExpected = $ExpectedSha256.ToUpperInvariant()
        Write-Host "BOOTLOADER expected sha256: [$normalizedExpected]"
        if ($actualSha256 -ne $normalizedExpected) {
            throw "BootloaderBin SHA256 mismatch."
        }
    }
}

function Write-PostWriteComparison {
    param(
        [string]$BootloaderPath,
        [string]$UserBeforePath,
        [string]$UserHeadBeforePath,
        [string]$BootBeforePath,
        [string]$UserAfterPath,
        [string]$UserHeadAfterPath,
        [string]$BootAfterPath,
        [string]$OutputPath
    )

    $userBeforeHash = Get-Sha256 -Path $UserBeforePath
    $userAfterHash = Get-Sha256 -Path $UserAfterPath
    $userHeadBeforeHash = Get-Sha256 -Path $UserHeadBeforePath
    $userHeadAfterHash = Get-Sha256 -Path $UserHeadAfterPath
    $bootBeforeHash = Get-Sha256 -Path $BootBeforePath
    $bootAfterHash = Get-Sha256 -Path $BootAfterPath
    $bootloaderHash = Get-Sha256 -Path $BootloaderPath

    $failures = @()
    if ($userBeforeHash -ne $userAfterHash) {
        $failures += "USER flash hash changed: before=[$userBeforeHash] after=[$userAfterHash]"
    }

    if ($userHeadBeforeHash -ne $userHeadAfterHash) {
        $failures += "USER head hash changed: before=[$userHeadBeforeHash] after=[$userHeadAfterHash]"
    }

    $bootPrefixMatches = "yes"
    try {
        Test-BinaryPrefix -ExpectedPath $BootloaderPath -ActualPath $BootAfterPath
    } catch {
        $bootPrefixMatches = "no"
        $failures += $_.Exception.Message
    }

    $lines = @(
        "USER before sha256: $userBeforeHash",
        "USER after sha256:  $userAfterHash",
        "USER unchanged: $(if ($userBeforeHash -eq $userAfterHash) { 'yes' } else { 'no' })",
        "USER head before sha256: $userHeadBeforeHash",
        "USER head after sha256:  $userHeadAfterHash",
        "USER head unchanged: $(if ($userHeadBeforeHash -eq $userHeadAfterHash) { 'yes' } else { 'no' })",
        "BOOT before sha256: $bootBeforeHash",
        "BOOT after sha256:  $bootAfterHash",
        "BOOTLOADER sha256:  $bootloaderHash",
        "BOOT after prefix matches bootloader: $bootPrefixMatches"
    )

    if ($failures.Count -gt 0) {
        $lines += "FAILURES:"
        $lines += $failures
    }

    $lines | Set-Content -LiteralPath $OutputPath -Encoding ASCII
    $lines | ForEach-Object { Write-Host $_ }

    if ($failures.Count -gt 0) {
        throw ("post-write comparison failed: " + ($failures -join "; "))
    }
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")

if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $EvidenceDir = Join-Path $root.Path "evidence\logs\boot-write-repro-$timestamp"
}

$resolvedEvidenceDir = New-Item -ItemType Directory -Force -Path $EvidenceDir
$readbackDir = New-Item -ItemType Directory -Force -Path (Join-Path $resolvedEvidenceDir.FullName "readback")

$openOcdPath = (Resolve-Path -LiteralPath $OpenOcdExe).Path
$configPath = Convert-ToTclPath -Path $Config
$resolvedRuntimePath = Resolve-RuntimePath -Paths $RuntimePath
$userSizeHex = "0x{0:x}" -f $UserSize
$userHeadSizeHex = "0x{0:x}" -f $UserHeadSize
$bootSizeHex = "0x{0:x}" -f $BootSize
$effectiveUseBankCommands = $UseBankCommands -or $PlanWrite -or $ExecuteWritePlanTrap -or $ExecuteWrite

if (($PlanWrite -or $ExecuteWritePlanTrap -or $ExecuteWrite) -and -not $UseBankCommands) {
    Write-Host "forcing bank commands for read-only preflight and write path"
}

if ($effectiveUseBankCommands) {
    Write-Host "expected bank[0]: [USER] [0x08000000] [$userSizeHex]"
    Write-Host "expected bank[1]: [BOOT] [0x1ffff000] [$bootSizeHex]"
}

$userBefore = (Join-Path $readbackDir.FullName "user-before.bin") -replace "\\", "/"
$userHeadBefore = (Join-Path $readbackDir.FullName "user-head-before.bin") -replace "\\", "/"
$bootBefore = (Join-Path $readbackDir.FullName "boot-before.bin") -replace "\\", "/"
$userAfter = (Join-Path $readbackDir.FullName "user-after.bin") -replace "\\", "/"
$userHeadAfter = (Join-Path $readbackDir.FullName "user-head-after.bin") -replace "\\", "/"
$bootAfter = (Join-Path $readbackDir.FullName "boot-after.bin") -replace "\\", "/"

$initCommand = "init"
$haltCommand = "halt"
$readStatrCommand = "mdw 0x4002200c 1"
$dumpUserBeforeCommand = "dump_image `"$userBefore`" 0x08000000 $userSizeHex"
$dumpUserHeadBeforeCommand = "dump_image `"$userHeadBefore`" 0x08000000 $userHeadSizeHex"
$dumpBootBeforeCommand = "dump_image `"$bootBefore`" 0x1ffff000 $bootSizeHex"
$flashProbeUserCommand = "flash probe 0"
$flashProbeBootCommand = "flash probe 1"
$flashBanksCommand = "flash banks"
$readBankUserBeforeCommand = "flash read_bank 0 `"$userBefore`" 0 $userSizeHex"
$readBankUserHeadBeforeCommand = "flash read_bank 0 `"$userHeadBefore`" 0 $userHeadSizeHex"
$readBankBootBeforeCommand = "flash read_bank 1 `"$bootBefore`" 0 $bootSizeHex"
$shutdownCommand = "shutdown"

if ($effectiveUseBankCommands) {
    $readOnlyArgs = @(
        "-f",
        $configPath,
        "-c",
        $initCommand,
        "-c",
        $haltCommand,
        "-c",
        $flashProbeUserCommand,
        "-c",
        $flashProbeBootCommand,
        "-c",
        $flashBanksCommand,
        "-c",
        $readStatrCommand,
        "-c",
        $readBankUserBeforeCommand,
        "-c",
        $readBankUserHeadBeforeCommand,
        "-c",
        $readBankBootBeforeCommand,
        "-c",
        $shutdownCommand
    )
} else {
    $readOnlyArgs = @(
        "-f",
        $configPath,
        "-c",
        $initCommand,
        "-c",
        $haltCommand,
        "-c",
        $readStatrCommand,
        "-c",
        $dumpUserBeforeCommand,
        "-c",
        $dumpUserHeadBeforeCommand,
        "-c",
        $dumpBootBeforeCommand,
        "-c",
        $shutdownCommand
    )
}

$readOnlyLog = Join-Path $resolvedEvidenceDir.FullName "01-readonly-baseline.log"
Invoke-LoggedOpenOcd -Exe $openOcdPath -Argv $readOnlyArgs -RuntimePath $resolvedRuntimePath -LogPath $readOnlyLog -Execute:$ExecuteReadOnly

if ($PlanWrite -or $ExecuteWritePlanTrap -or $ExecuteWrite) {
    if ($ExecuteWrite -and -not $ConfirmWriteToBoot) {
        throw "-ConfirmWriteToBoot is required with -ExecuteWrite."
    }

    Assert-BootloaderInput -Path $BootloaderBin -MaxSize $BootSize -ExpectedSha256 $ExpectedBootloaderSha256 -RequireExpectedSha256:$ExecuteWrite

    $bootloaderItem = Get-Item -LiteralPath $BootloaderBin
    $bootloaderSize = [int]$bootloaderItem.Length
    $bootloaderPath = Convert-ToTclPath -Path $BootloaderBin
    $pageEraseCommand = "page_erase"
    $writePlanTrapCommand = "wlink_write_plan_trap on"
    $writeBankBootCommand = "flash write_bank 1 `"$bootloaderPath`" 0"
    $verifyBankBootCommand = "flash verify_bank 1 `"$bootloaderPath`" 0"
    $readBankUserAfterCommand = "flash read_bank 0 `"$userAfter`" 0 $userSizeHex"
    $readBankUserHeadAfterCommand = "flash read_bank 0 `"$userHeadAfter`" 0 $userHeadSizeHex"
    $readBankBootAfterCommand = "flash read_bank 1 `"$bootAfter`" 0 $bootSizeHex"

    Write-Host "WRITE target: [0x1ffff000]"
    Write-Host "WRITE erase mode: [page_erase global flag before init/write]"
    Write-Host "WRITE command: [flash write_bank 1] [offset 0]"
    if ($ExecuteWritePlanTrap) {
        Write-Host "WRITE plan trap: [enabled before init; abort before wlink_ready_write]"
    }
    Write-Host "USER invariant range: [0x08000000] [$userSizeHex]"
    Write-Host "BOOT readback range: [0x1ffff000] [$bootSizeHex]"

    $writeArgs = @(
        "-f",
        $configPath,
        "-c",
        $pageEraseCommand
    )
    if ($ExecuteWritePlanTrap) {
        $writeArgs += @(
            "-c",
            $writePlanTrapCommand
        )
    }
    $writeArgs += @(
        "-c",
        $initCommand,
        "-c",
        $haltCommand,
        "-c",
        $flashProbeUserCommand,
        "-c",
        $flashProbeBootCommand,
        "-c",
        $flashBanksCommand,
        "-c",
        $readBankUserBeforeCommand,
        "-c",
        $readBankUserHeadBeforeCommand,
        "-c",
        $readBankBootBeforeCommand,
        "-c",
        $writeBankBootCommand,
        "-c",
        $verifyBankBootCommand,
        "-c",
        $haltCommand,
        "-c",
        $readBankUserAfterCommand,
        "-c",
        $readBankUserHeadAfterCommand,
        "-c",
        $readBankBootAfterCommand,
        "-c",
        $shutdownCommand
    )

    $writeLog = Join-Path $resolvedEvidenceDir.FullName "02-write-and-readback.log"
    $writeError = $null
    $executeWriteCommand = $ExecuteWrite -or $ExecuteWritePlanTrap
    try {
        Invoke-LoggedOpenOcd -Exe $openOcdPath -Argv $writeArgs -RuntimePath $resolvedRuntimePath -LogPath $writeLog -Execute:$executeWriteCommand
    } catch {
        $writeError = $_
        if (-not $ExecuteWrite -and -not $ExecuteWritePlanTrap) {
            throw
        }
        if ($ExecuteWritePlanTrap) {
            Write-Warning "write command stopped by expected plan trap"
        } else {
            Write-Warning "write command failed; running independent post-write readback"
        }
    }

    if ($ExecuteWritePlanTrap) {
        if (-not $writeError) {
            throw "write plan trap was enabled, but OpenOCD did not stop with an error."
        }
        Assert-WritePlanTrapLog -LogPath $writeLog -BootloaderSize $bootloaderSize
        Write-Host "write plan trap validated"
    }

    if ($ExecuteWrite) {
        if ($writeError) {
            $postReadbackArgs = @(
                "-f",
                $configPath,
                "-c",
                $initCommand,
                "-c",
                $haltCommand,
                "-c",
                $flashProbeUserCommand,
                "-c",
                $flashProbeBootCommand,
                "-c",
                $flashBanksCommand,
                "-c",
                $readBankUserAfterCommand,
                "-c",
                $readBankUserHeadAfterCommand,
                "-c",
                $readBankBootAfterCommand,
                "-c",
                $shutdownCommand
            )
            $postReadbackLog = Join-Path $resolvedEvidenceDir.FullName "02b-post-error-readback.log"
            Invoke-LoggedOpenOcd -Exe $openOcdPath -Argv $postReadbackArgs -RuntimePath $resolvedRuntimePath -LogPath $postReadbackLog -Execute
        }

        $comparePath = Join-Path $resolvedEvidenceDir.FullName "03-post-write-compare.txt"
        try {
            Write-PostWriteComparison `
                -BootloaderPath $BootloaderBin `
                -UserBeforePath (Convert-FromTclPath -Path $userBefore) `
                -UserHeadBeforePath (Convert-FromTclPath -Path $userHeadBefore) `
                -BootBeforePath (Convert-FromTclPath -Path $bootBefore) `
                -UserAfterPath (Convert-FromTclPath -Path $userAfter) `
                -UserHeadAfterPath (Convert-FromTclPath -Path $userHeadAfter) `
                -BootAfterPath (Convert-FromTclPath -Path $bootAfter) `
                -OutputPath $comparePath
        } catch {
            if ($writeError) {
                throw ("write command failed and post-write comparison failed: " + $writeError.Exception.Message + " / " + $_.Exception.Message)
            }
            throw
        }

        if ($writeError) {
            throw $writeError
        }
    }
}

Get-ChildItem -File -Recurse -LiteralPath $resolvedEvidenceDir.FullName |
    Where-Object { $_.Extension -in ".bin", ".log", ".txt" } |
    Get-FileHash -Algorithm SHA256 |
    Tee-Object -FilePath (Join-Path $resolvedEvidenceDir.FullName "sha256.txt")
