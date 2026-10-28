#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Enable','Check','Restore','BerryOff')][string]$Action='Enable',
    [string]$Target='169.254.0.1',
    [string]$Key,
    [switch]$ChooseKey,
    [switch]$Refresh,
    [switch]$NoDialog
)
$ErrorActionPreference='Stop'
# A parent PowerShell 7 session can leave incompatible modules on PSModulePath.
Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1" -ErrorAction Stop
Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1" -ErrorAction Stop
$root=Split-Path $PSScriptRoot -Parent
$cache=Join-Path $env:LOCALAPPDATA 'BB10VoLTE'
$log=$null
function Say([string]$Text,[string]$Color='Cyan') {
    Write-Host $Text -ForegroundColor $Color
    if ($script:log) { Add-Content -LiteralPath $script:log -Value $Text -Encoding UTF8 }
}
function Run-Native([string]$Exe,[string[]]$Arguments,[string]$InputText,[switch]$Live) {
    $saved=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        if ($InputText) { $output=@($InputText | & $Exe @Arguments 2>&1) }
        elseif ($Live) {
            $output=@(& $Exe @Arguments 2>&1 | ForEach-Object {
                $line=$_.ToString()
                Decode-Markers ([pscustomobject]@{Lines=@($line)})
                $line
            })
        } else { $output=@(& $Exe @Arguments 2>&1) }
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$saved }
    $lines=@($output | ForEach-Object { $_.ToString() })
    if ($script:log -and $lines.Count) { Add-Content -LiteralPath $script:log -Value $lines -Encoding UTF8 }
    return [pscustomobject]@{ Code=$code; Lines=$lines }
}
function Find-Key {
    if ($Key) {
        if (!(Test-Path -LiteralPath $Key -PathType Leaf)) { throw '指定的私钥文件不存在。' }
        return (Resolve-Path -LiteralPath $Key).Path
    }
    $settings=Join-Path $cache 'settings.json'
    $candidates=@()
    if (Test-Path -LiteralPath $settings) {
        try { $candidates+=((Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).Key) } catch {}
    }
    $candidates+=@((Join-Path $env:USERPROFILE '.ssh\bb_root_key'), (Join-Path $root 'keys\bb_root_key'), (Join-Path $root 'keys\id_rsa'))
    foreach ($candidate in $candidates) {
        if (!$ChooseKey -and $candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    if ($NoDialog) { throw '未找到 root 私钥。请使用 -Key 参数指定，或把自己的私钥放入 keys 文件夹并命名为 bb_root_key。' }
    Say '首次使用：请选择这台手机越狱时使用的 root SSH 私钥（不是 .pub 文件，也不是手机密码）。' Yellow
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title='选择这台黑莓的 root SSH 私钥（不是 .pub 公钥）'
    $dialog.Filter='所有文件 (*.*)|*.*'
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw '未选择私钥，操作已取消。' }
        return $dialog.FileName
    } finally { $dialog.Dispose() }
}
function Install-Key([string]$Source) {
    $header=Get-Content -LiteralPath $Source -TotalCount 1
    if ($header -notmatch '^-----BEGIN (OPENSSH |RSA |EC |ENCRYPTED )?PRIVATE KEY-----') {
        throw '选择的文件不是 OpenSSH/PEM 私钥。请勿选择 .pub 公钥或 PuTTY .ppk 文件。'
    }
    $keyDir=Join-Path $cache 'keys'
    New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
    $digest=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.Substring(0,16)
    $dest=Join-Path $keyDir "key-$digest"
    $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl=New-Object System.Security.AccessControl.FileSecurity
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true,$false)
    $rule=New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')
    $acl.AddAccessRule($rule)
    if (!(Test-Path -LiteralPath $dest)) {
        # Restrict the new file before writing any private-key material into it.
        [IO.File]::WriteAllText($dest,'')
        [IO.File]::SetAccessControl($dest,$acl)
        [IO.File]::WriteAllBytes($dest,[IO.File]::ReadAllBytes($Source))
    } else {
        $existing=[IO.File]::GetAccessControl($dest)
        $owner=$existing.GetOwner([Security.Principal.SecurityIdentifier])
        $rules=$existing.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
        if ($owner -ne $sid -or !$existing.AreAccessRulesProtected -or @($rules | Where-Object {$_.IdentityReference -ne $sid}).Count) {
            throw '缓存私钥的权限异常。请删除 %LOCALAPPDATA%\BB10VoLTE\keys 后重新选择自己的私钥。'
        }
    }
    @{Key=$dest} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $cache 'settings.json') -Encoding UTF8
    return $dest
}
function Decode-Markers($Result) {
    $map=@{
        'COMPATIBLE'='机型、系统和网络组件检查通过。'
        'SIM_LTE_OK'='中国移动 SIM 已就绪，当前为 4G 网络。'
        'BACKUP_CREATED'='已备份这台手机首次运行前的配置。'
        'BACKUP_EXISTS'='原始备份已存在，已保留。'
        'APPLYING'='正在应用 VoLTE 配置……'
        'CONNECTED'='成功：VoLTE 已在 LTE 上注册。'
        'ALREADY_CONNECTED'='成功：VoLTE 已连接，莓标监控已就绪，无需重启通话服务。'
        'NOT_CONNECTED'='VoLTE 尚未注册。'
        'BERRY_RUNNING'='莓标联动正在运行。'
        'BERRY_STOPPED'='莓标联动尚未运行。'
        'BERRY_DISABLED'='莓标联动已停用，VoLTE 配置保持不变。'
        'RESTORED'='已恢复到本工具首次运行前的配置。'
        'ROLLBACK_STARTED'='启用未完成，正在自动恢复此前配置……'
        'ROLLBACK_OK'='自动恢复完成。'
    }
    $errors=@{
        'OS_UNSUPPORTED'='系统版本不匹配：本版仅支持 BB10 10.3.3.3216。'
        'MODEL_UNSUPPORTED'='机型不匹配：本版仅支持 Classic AT&T（CLASSICATT）。'
        'STACK_UNSUPPORTED'='网络组件与已验证版本不同，已停止操作。'
        'ROOT_REQUIRED'='没有取得 root 权限，请检查越狱状态和 root 私钥。'
        'CALL_ACTIVE'='手机正在通话或电话服务未就绪，请挂断后再试。'
        'SIM_NOT_READY'='SIM 尚未就绪。请在手机上解锁 SIM，勿反复尝试 PIN。'
        'SIM_UNSUPPORTED'='SIM 不匹配：本版只验证并支持中国移动 460-00。'
        'LTE_REQUIRED'='当前没有连接 4G。请关闭飞行模式，开启移动网络并等待 4G 后再试。'
        'BACKUP_INCOMPLETE'='发现未完成的备份，已停止写入。请保留日志，联系工具提供者处理。'
        'CONFIG_NOT_REGULAR'='发现非标准配置文件，已停止操作。'
        'XML_BACKUP_FAILED'='运营商配置备份失败，已停止操作。'
        'OPERATION_BUSY'='另一项手机配置操作正在运行。请等待它完成。'
        'REGISTER_TIMEOUT'='等待 60 秒后 VoLTE 仍未注册。请查看下方自动恢复结果。'
        'ROLLBACK_FAILED'='自动恢复未完成。请保持 USB 连接，运行「恢复原配置.cmd」并保留日志。'
        'NO_BACKUP'='手机没有本工具的完整备份，无法恢复。未使用别人的备份。'
        'BERRY_START_FAILED'='莓标监控启动失败。'
        'IMS_STOP_FAILED'='电话网络进程未能正常停止，已中止操作。'
        'BERRY_STOP_FAILED'='莓标进程未能正常停止，已中止操作。'
    }
    foreach ($line in $Result.Lines) {
        if ($line -match '^BBE:ERROR:(.+)$') {
            $code=$Matches[1]
            if ($errors.ContainsKey($code)) { Say "[错误] $($errors[$code])" Red }
            else { Say "[错误] $code" Red }
        } elseif ($line -match '^BBE:WAITING:(\d+)$') {
            Say "正在等待运营商注册……已等待 $($Matches[1]) 秒。"
        } elseif ($line -match '^BBE:(.+)$' -and $map.ContainsKey($Matches[1])) {
            $code=$Matches[1]
            $color=if ($code -in @('CONNECTED','ALREADY_CONNECTED','RESTORED','ROLLBACK_OK')) { 'Green' } else { 'Cyan' }
            Say $map[$code] $color
        }
    }
}
function Assert-SSH($Result) {
    if ($Result.Code -eq 0) { return }
    $all=$Result.Lines -join "`n"
    if ($all -match 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed') {
        throw '手机 SSH 身份与上次不同。若更换了手机或重新越狱，请删除 %LOCALAPPDATA%\BB10VoLTE\known_hosts 中对应旧记录后再试。'
    }
    if ($all -match 'Permission denied|Load key|bad permissions|invalid format') {
        throw 'root 私钥登录失败。请双击「重新选择私钥.cmd」选择这台手机自己的正确私钥；带口令的私钥需先由 ssh-agent 解锁。'
    }
    if ($all -match 'Connection refused|Connection timed out|No route to host|Connection reset') {
        throw '无法连接手机。请解锁手机、打开开发模式，重新插拔支持数据传输的 USB 线，然后重试。'
    }
    if ($all -match '^BBE:ERROR:' -or $all -match '\nBBE:ERROR:') { throw '本次操作未完成，具体原因见上方提示。' }
    throw 'SSH 或手机操作失败。详细错误已保存到日志。'
}

try {
    Write-Host ''
    Write-Host '黑莓 Classic 中国移动 VoLTE 一键工具 1.0' -ForegroundColor White
    Write-Host '支持范围：Classic AT&T / BB10 10.3.3.3216 / 中国移动 460-00'
    Write-Host ''
    $ip=$null
    if (![Net.IPAddress]::TryParse($Target,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Target 必须是 IPv4 地址。' }
    foreach ($relative in @('ssh.exe','scp.exe')) {
        if (!(Test-Path -LiteralPath (Join-Path "$env:WINDIR\System32\OpenSSH" $relative))) {
            throw '电脑未安装 Windows OpenSSH 客户端。请在 Windows 设置的「可选功能」中安装 OpenSSH 客户端后重试，无需安装服务器。'
        }
    }
    $ssh=Join-Path "$env:WINDIR\System32\OpenSSH" 'ssh.exe'
    $scp=Join-Path "$env:WINDIR\System32\OpenSSH" 'scp.exe'
    $manifest=Get-Content -LiteralPath (Join-Path $root 'SHA256.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.PSObject.Properties) {
        $file=Join-Path $root $entry.Name
        if (!(Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.Value) {
            throw "工具文件缺失或损坏：$($entry.Name)。请完整解压原始压缩包后重试。"
        }
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $cache 'logs') | Out-Null
    $script:log=Join-Path $cache ("logs\{0}-{1}-{2}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$Action,$PID)
    Say '[1/4] 检查 USB 连接……'
    $tcp=New-Object Net.Sockets.TcpClient
    try {
        $connecting=$tcp.ConnectAsync($Target,22)
        if (!$connecting.Wait(3000) -or !$tcp.Connected) { throw '连接超时' }
    } catch { throw '没有找到 USB SSH 连接。请先解锁手机，开启开发模式，连接数据线；本工具不会扫描虚拟机或其他网络设备。' }
    finally { $tcp.Dispose() }
    $keyPath=Install-Key (Find-Key)
    $knownHosts=Join-Path $cache 'known_hosts'
    $opts=@('-F','NUL','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=3','-o','StrictHostKeyChecking=accept-new','-o',"UserKnownHostsFile=$knownHosts",'-o','GlobalKnownHostsFile=NUL','-o','HostKeyAlgorithms=+ssh-rsa','-o','PubkeyAcceptedKeyTypes=+ssh-rsa','-o','MACs=+hmac-sha1','-o','IdentitiesOnly=yes','-i',$keyPath)
    $destination="root@$Target"
    Say '[2/4] 验证 root、机型和系统……'
    $remoteScript=[IO.File]::ReadAllText((Join-Path $root 'payload\easy-device.sh')).Replace("`r`n","`n")+"`nexit`n"
    $preAction=if ($Action -in @('Restore','BerryOff')) { 'Probe' } else { 'Check' }
    $pre=Run-Native $ssh ($opts+@($destination,"sh -s $preAction")) $remoteScript
    Decode-Markers $pre
    Assert-SSH $pre
    if ($Action -eq 'Check') { Say '检测完成，没有更改手机配置。' Green; exit 0 }
    Say '[3/4] 发送工具组件……'
    $prepare=Run-Native $ssh ($opts+@($destination,'mkdir -p /var/tmp/bb10-volte && chmod 755 /var/tmp/bb10-volte'))
    Assert-SSH $prepare
    $scpOpts=$opts
    $version=Run-Native $ssh @('-V')
    if (($version.Lines -join ' ') -match 'OpenSSH[^0-9]*(\d+)' -and [int]$Matches[1] -ge 9) { $scpOpts=@('-O')+$opts }
    foreach ($name in @('easy-device.sh','carrier-404-volte.xml','devnp-volte-swcrypto.so','volte-berry')) {
        $sent=Run-Native $scp ($scpOpts+@((Join-Path $root "payload\$name"),"${destination}:/var/tmp/bb10-volte/$name.new"))
        Assert-SSH $sent
        $installed=Run-Native $ssh ($opts+@($destination,"mv /var/tmp/bb10-volte/$name.new /var/tmp/bb10-volte/$name"))
        Assert-SSH $installed
    }
    Say '[4/4] 执行操作，请保持 USB 连接……'
    $remoteAction=$Action
    if ($Refresh -and $Action -eq 'Enable') { $remoteAction+=' Refresh' }
    $run=Run-Native $ssh ($opts+@($destination,"sh /var/tmp/bb10-volte/easy-device.sh $remoteAction")) $null -Live
    # Keep backups and logs outside the shareable program folder.
    if ($Action -in @('Enable','Restore')) {
        $backupLocal=Join-Path $cache ("backups\$Target\"+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Force -Path $backupLocal | Out-Null
        $copied=Run-Native $scp ($scpOpts+@('-r',"${destination}:/var/tmp/bb10-volte/easy-backup-v1",$backupLocal))
        if ($copied.Code -eq 0) { Say "备份副本：$backupLocal" DarkGray }
        else { Say '电脑端备份副本未能下载；手机端备份仍保留。详情见日志。' Yellow }
    }
    Assert-SSH $run
    if ($Action -eq 'Enable') {
        Say '可以拔掉 USB 使用。手机重启后，请再次双击「一键启动.cmd」。' Green
        Say '注册成功不等于所有通话均已验证，可自行拨打运营商查询号码试听。' DarkGray
    }
    Say "日志：$script:log" DarkGray
    exit 0
} catch {
    Say "[未完成] $($_.Exception.Message)" Red
    if ($script:log) { Say "日志：$script:log" Yellow }
    exit 1
}
