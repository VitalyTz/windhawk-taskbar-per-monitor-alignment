param([string]$WindhawkPath = 'C:\Program Files\Windhawk')
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $WindhawkPath 'Compiler\bin\clang++.exe'
$flags = Join-Path $WindhawkPath 'Compiler\compile_flags.txt'
$ini = Get-Content (Join-Path $WindhawkPath 'windhawk.ini')
$engineRelative = ($ini | Where-Object { $_ -match '^EnginePath=' }) -replace '^EnginePath=', ''
if (-not $engineRelative) { throw 'EnginePath missing in windhawk.ini' }
$library = Join-Path $WindhawkPath "$engineRelative\64\windhawk.lib"
$output = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Force $output | Out-Null
# Define the mod id through a header: an embedded-quote argument survives neither
# PowerShell edition's native-command quoting reliably.
$modId = Join-Path $output 'mod_id.h'
Set-Content -LiteralPath $modId -Encoding ASCII -Value '#define WH_MOD_ID L"taskbar-per-monitor-alignment"'
& $compiler -include $modId "@$flags" '-UWH_EDITING' -shared -O2 -Wall -Wextra (Join-Path $PSScriptRoot 'taskbar-per-monitor-alignment.wh.cpp') -x none $library -lole32 -loleaut32 -lruntimeobject -luuid -lcomctl32 -o (Join-Path $output 'taskbar-per-monitor-alignment.dll')
if ($LASTEXITCODE) { throw "Mod compilation failed: $LASTEXITCODE" }
& $compiler -include $modId "@$flags" (Join-Path $PSScriptRoot 'tests.cpp') -lole32 -loleaut32 -lruntimeobject -luuid -lcomctl32 -o (Join-Path $output 'tests.exe')
if ($LASTEXITCODE) { throw "Test compilation failed: $LASTEXITCODE" }
# Windhawk's target runtime imports use .whl names, not the compiler-host DLLs.
$runtime = Join-Path $WindhawkPath 'Compiler\x86_64-w64-mingw32\bin'
Copy-Item -LiteralPath (Join-Path $runtime 'libc++.dll') -Destination (Join-Path $output 'libc++.whl') -Force
Copy-Item -LiteralPath (Join-Path $runtime 'libunwind.dll') -Destination (Join-Path $output 'libunwind.whl') -Force
Copy-Item -LiteralPath (Join-Path $runtime 'windhawk-mod-shim.dll') -Destination $output -Force
& (Join-Path $output 'tests.exe')
if ($LASTEXITCODE) { throw "Tests failed: $LASTEXITCODE" }
Write-Host "Built and tested: $output\taskbar-per-monitor-alignment.dll"



