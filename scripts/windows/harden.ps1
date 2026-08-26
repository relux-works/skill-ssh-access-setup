$ErrorActionPreference = 'Stop'
function Fail([string]$Code, [string]$Action) { [Console]::Error.WriteLine("error_code=$Code"); [Console]::Error.WriteLine("action=$Action"); exit 1 }
$sshAlias = ''; $targetOs = ''; $apply = $false; $verifyOnly = $false
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--alias' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --alias.' }; $sshAlias = $args[$index] }
        '--target-os' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --target-os.' }; $targetOs = $args[$index] }
        '--apply' { $apply = $true }
        '--verify' { $verifyOnly = $true }
        default { Fail 'invalid_arguments' 'Use --target-os PLATFORM --alias NAME [--apply | --verify].' }
    }
}
if ($targetOs -notin @('macos', 'linux', 'windows')) { Fail 'invalid_target_os' 'Use macos, linux, or windows.' }
if (-not $sshAlias) { Fail 'invalid_arguments' 'Provide --alias NAME.' }
if ($apply -and $verifyOnly) { Fail 'invalid_arguments' 'Choose either --apply or --verify.' }

function Verify-KeyOnly {
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $sshAlias 'exit 0' 2>$null
    if ($LASTEXITCODE -ne 0) { [Console]::Out.WriteLine('schema_version=1'); [Console]::Out.WriteLine("alias=$sshAlias"); [Console]::Out.WriteLine('key_auth=failed'); [Console]::Out.WriteLine('password_auth=not_checked'); return $false }
    $authenticationOutput = (& ssh -vv -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive $sshAlias 'exit 0' 2>&1 | Out-String)
    [Console]::Out.WriteLine('schema_version=1'); [Console]::Out.WriteLine("alias=$sshAlias"); [Console]::Out.WriteLine('key_auth=ok')
    if ($authenticationOutput -match 'Authentications that can continue:.*(password|keyboard-interactive)') { [Console]::Out.WriteLine('password_auth=enabled'); return $false }
    if ($authenticationOutput -match 'Authentications that can continue:.*publickey') { [Console]::Out.WriteLine('password_auth=disabled'); return $true }
    [Console]::Out.WriteLine('password_auth=unknown'); return $false
}
if ($verifyOnly) { if (Verify-KeyOnly) { exit 0 } else { exit 1 } }
$remoteFile = if ($targetOs -eq 'windows') { '%ProgramData%\ssh\sshd_config' } else { '/etc/ssh/sshd_config.d/00-ssh-access-key-only.conf' }
$action = if ($apply) { 'apply' } else { 'preview' }; $status = if ($apply) { 'applying' } else { 'would_harden' }
Write-Output 'schema_version=1'; Write-Output "action=$action"; Write-Output "status=$status"; Write-Output "target_os=$targetOs"; Write-Output "alias=$sshAlias"; Write-Output "remote_file=$remoteFile"; Write-Output 'requires=administrator_privileges'
if (-not $apply) { exit 0 }
& ssh -o BatchMode=yes -o ConnectTimeout=10 $sshAlias 'exit 0' 2>$null
if ($LASTEXITCODE -ne 0) { Fail 'key_auth_required' 'Install and verify the public key before hardening SSH.' }
$payloadRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\payloads')).Path
if ($targetOs -eq 'windows') {
    & scp -o BatchMode=yes (Join-Path $payloadRoot 'harden-windows.ps1') "${sshAlias}:"
    if ($LASTEXITCODE -ne 0) { Fail 'payload_transfer_failed' 'Verify SCP support and the remote home directory.' }
    & ssh -o BatchMode=yes $sshAlias 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\harden-windows.ps1'
    if ($LASTEXITCODE -ne 0) { Fail 'administrator_auth_required' 'Run the staged PowerShell payload from an elevated retained session.' }
} else {
    & scp -o BatchMode=yes (Join-Path $payloadRoot 'key-only.conf') (Join-Path $payloadRoot 'harden-unix.sh') "${sshAlias}:/tmp/"
    if ($LASTEXITCODE -ne 0) { Fail 'payload_transfer_failed' 'Verify SCP access to /tmp.' }
    & ssh -o BatchMode=yes $sshAlias "sudo -n /bin/sh /tmp/harden-unix.sh '$targetOs'"
    if ($LASTEXITCODE -ne 0) { Fail 'administrator_auth_required' "Run interactively: ssh -t $sshAlias \"sudo /bin/sh /tmp/harden-unix.sh '$targetOs'\"" }
}
if (Verify-KeyOnly) { exit 0 } else { exit 1 }
