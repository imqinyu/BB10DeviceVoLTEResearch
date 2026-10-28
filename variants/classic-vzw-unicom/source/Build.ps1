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
& $gcc -shared -fPIC -mthumb -march=armv7-a -O2 -Wall -Wextra -Werror -o "$root\payload\devnp-volte-swcrypto.so" "$PSScriptRoot\devnp-volte-swcrypto.c"
if ($LASTEXITCODE) { throw 'Provider build failed.' }
& $gcc -mthumb -march=armv7-a -O2 -fPIE -pie -Wall -Wextra -Werror -o "$root\payload\volte-berry" "$PSScriptRoot\volte-berry.c" -lpps
if ($LASTEXITCODE) { throw 'Indicator build failed.' }
$manifest=[ordered]@{}
Get-ChildItem "$root\payload" -File | ForEach-Object { $manifest['payload/'+$_.Name]=(Get-FileHash $_.FullName -Algorithm SHA256).Hash }
$manifest['scripts/BB10-VoLTE.ps1']=(Get-FileHash "$root\scripts\BB10-VoLTE.ps1" -Algorithm SHA256).Hash
$manifest | ConvertTo-Json | Set-Content "$root\SHA256.json" -Encoding UTF8
Write-Host 'Build and SHA256 manifest updated.'
