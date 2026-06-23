param(
    [string]$DllTool = '',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\build\wlinke-mingw32-deps\lib'),
    [string]$DllName = 'libusb-1.0.dll'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DllTool)) {
    $dllToolCommand = Get-Command 'dlltool.exe' -ErrorAction SilentlyContinue
    if ($null -eq $dllToolCommand) {
        throw 'dlltool.exe not found. Pass -DllTool or add the MinGW bin directory to PATH.'
    }
    $DllTool = $dllToolCommand.Source
}

if (-not (Test-Path -LiteralPath $DllTool)) {
    throw "dlltool not found: $DllTool"
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$defPath = Join-Path $OutDir 'libusb-1.0-stdcall.def'
$outPath = Join-Path $OutDir 'libusb-1.0-stdcall-kill-at.dll.a'

# The 32-bit libusb header uses WINAPI/stdcall, but the WCH-distributed DLL
# exports undecorated names.  The DEF keeps @N link symbols and --kill-at makes
# the runtime DLL lookup names undecorated.
$defText = @"
LIBRARY "$DllName"
EXPORTS
    libusb_bulk_transfer@24
    libusb_claim_interface@8
    libusb_close@4
    libusb_control_transfer@32
    libusb_error_name@4
    libusb_exit@4
    libusb_free_config_descriptor@4
    libusb_free_device_list@8
    libusb_get_bus_number@4
    libusb_get_config_descriptor@12
    libusb_get_configuration@8
    libusb_get_device@4
    libusb_get_device_descriptor@8
    libusb_get_device_list@8
    libusb_get_port_numbers@12
    libusb_get_string_descriptor_ascii@16
    libusb_handle_events_completed@8
    libusb_init@4
    libusb_open@8
    libusb_set_configuration@8
"@

Set-Content -LiteralPath $defPath -Value $defText -Encoding ASCII

$machine = 'i386'
$argsList = @(
    '-d',
    $defPath,
    '-l',
    $outPath,
    '--dllname',
    $DllName,
    '--kill-at',
    '-m',
    $machine
)

$formattedArgs = ($argsList | ForEach-Object { '[' + $_ + ']' }) -join ' '
Write-Host "dlltool argv: $formattedArgs"
& $DllTool @argsList
if ($LASTEXITCODE -ne 0) {
    throw "dlltool failed with exit code $LASTEXITCODE"
}

$generatedPaths = @(
    $defPath,
    $outPath
)

foreach ($generatedPath in $generatedPaths) {
    $generatedItem = Get-Item -LiteralPath $generatedPath
    Write-Host ("generated: [{0}] [{1} bytes] [{2}]" -f $generatedItem.FullName, $generatedItem.Length, $generatedItem.LastWriteTime)
}
