#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$NdkHost,
    [Parameter(Mandatory)][string]$NdkTarget
)
$ErrorActionPreference='Stop'
$env:QNX_HOST=$NdkHost.Replace('\','/')
$env:QNX_TARGET=$NdkTarget.Replace('\','/')
$env:PATH="$NdkHost\usr\bin;$env:PATH"
$gcc=Join-Path $NdkHost 'usr\bin\ntoarmv7-gcc.exe'
$root=Split-Path $PSScriptRoot -Parent
$out=Join-Path $root 'build\armv7'
New-Item -ItemType Directory -Force -Path $out | Out-Null
& $gcc -shared -fPIC -mthumb -march=armv7-a -O2 -Wall -Wextra -Werror -o "$out\devnp-volte-swcrypto.so" "$root\src\devnp-volte-swcrypto.c"
if ($LASTEXITCODE) { throw 'Provider build failed.' }
& $gcc -mthumb -march=armv7-a -O2 -fPIE -pie -Wall -Wextra -Werror -o "$out\volte-berry" "$root\src\volte-berry.c" -lpps
if ($LASTEXITCODE) { throw 'Indicator build failed.' }
Write-Host "Built baseline sources into $out (archived binaries were not overwritten)."
