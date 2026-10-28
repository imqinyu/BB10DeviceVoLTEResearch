#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$Target='169.254.0.1'
)
$ErrorActionPreference='Stop'
Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1"
Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1"
$address=$null
if (![Net.IPAddress]::TryParse($Target,[ref]$address) -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'Target must be an IPv4 address.'
}
if (!(Test-Path -LiteralPath $Key -PathType Leaf)) { throw 'Root SSH key not found.' }
$ssh=Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
if (!(Test-Path -LiteralPath $ssh)) { throw 'Windows OpenSSH client is required.' }
$options=@('-F','NUL','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=8',
    '-o','HostKeyAlgorithms=+ssh-rsa','-o','PubkeyAcceptedKeyTypes=+ssh-rsa','-o','MACs=+hmac-sha1',
    '-o','IdentitiesOnly=yes','-i',(Resolve-Path -LiteralPath $Key).Path,"root@$Target",'sh')
$scriptText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'collect-public-evidence.sh')).Replace("`r`n","`n")+"`nexit`n"
$saved=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    $raw=@($scriptText | & $ssh @options 2>&1)
    $code=$LASTEXITCODE
} finally { $ErrorActionPreference=$saved }
if ($code -ne 0) { throw 'Read-only SSH collection failed; no output file was written. Check SSH/key/known-host setup.' }
$lines=@($raw | ForEach-Object {$_.ToString()})
$begin=[Array]::IndexOf($lines,'BB10_PUBLIC_EVIDENCE_BEGIN')
$end=[Array]::IndexOf($lines,'BB10_PUBLIC_EVIDENCE_END')
if ($begin -lt 0 -or $end -le $begin) { throw 'Incomplete collection markers; no output file was written.' }
$content=@('# Read-only BB10 public evidence',
    ('# Collected at '+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')),
    '# No dialing, service restart, provider load, trust change or PPS write was performed.',
    '# SIM home PLMN is included; subscriber/device identities are not.')+$lines[($begin+1)..($end-1)]
$full=[IO.Path]::GetFullPath($OutFile)
$parent=Split-Path $full -Parent
if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($full,($content -join "`n")+"`n",(New-Object Text.UTF8Encoding($false)))
Write-Host "Read-only public evidence saved: $full"
