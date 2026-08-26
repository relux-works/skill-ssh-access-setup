$ErrorActionPreference = 'Stop'
function Fail([string]$Code, [string]$Action) { [Console]::Error.WriteLine("error_code=$Code"); [Console]::Error.WriteLine("action=$Action"); exit 1 }
$targetOs = ''; $targetHost = ''; $remoteUser = ''; $publicKey = ''; $proxyJump = ''; $transport = 'direct'; $port = 22; $apply = $false
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--target-os' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --target-os.' }; $targetOs = $args[$index] }
        '--host' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --host.' }; $targetHost = $args[$index] }
        '--user' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --user.' }; $remoteUser = $args[$index] }
        '--public-key' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --public-key.' }; $publicKey = $args[$index] }
        '--port' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --port.' }; $port = $args[$index] }
        '--proxy-jump' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --proxy-jump.' }; $proxyJump = $args[$index] }
        '--transport' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --transport.' }; $transport = $args[$index] }
        '--apply' { $apply = $true }
        default { Fail 'invalid_arguments' 'Use target, endpoint, account, public key, and optional route arguments.' }
    }
}
if ($targetOs -notin @('macos', 'linux', 'windows')) { Fail 'invalid_target_os' 'Use macos, linux, or windows.' }
if (-not ($targetHost -and $remoteUser) -or -not (Test-Path -LiteralPath $publicKey -PathType Leaf)) { Fail 'invalid_arguments' 'Resolve host, user, and an existing public key.' }
if ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { Fail 'invalid_port' 'Use a TCP port from 1 through 65535.' }
if ($targetHost -notmatch '^[A-Za-z0-9._:%-]+$') { Fail 'invalid_host' 'Use a valid hostname, IPv4 address, or IPv6 address.' }
if ($remoteUser -notmatch '^[A-Za-z0-9._@\\-]+$') { Fail 'invalid_user' 'Use the verified remote account name.' }
if ($transport -notmatch '^[A-Za-z0-9._-]+$') { Fail 'invalid_transport' 'Use a short transport label without spaces.' }
if ($proxyJump -and $proxyJump -match '[\s#]') { Fail 'invalid_proxy_jump' 'Use an SSH alias or a compact OpenSSH jump specification.' }
$fingerprint = (& ssh-keygen -lf $publicKey 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Fail 'invalid_public_key' 'Inspect or replace the selected public key.' }
$action = if ($apply) { 'apply' } else { 'preview' }; $status = if ($apply) { 'authorizing' } else { 'would_authorize' }
Write-Output 'schema_version=1'; Write-Output "action=$action"; Write-Output "status=$status"; Write-Output "target_os=$targetOs"; Write-Output "transport=$transport"; Write-Output "target=$targetHost"; Write-Output "port=$port"; Write-Output "proxy_jump=$(if ($proxyJump) { $proxyJump } else { 'none' })"; Write-Output "user=$remoteUser"; Write-Output "public_key=$publicKey"; Write-Output "fingerprint=$fingerprint"; Write-Output 'requires=interactive_remote_authentication'
if (-not $apply) { exit 0 }
foreach ($commandName in @('ssh', 'scp')) { if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) { Fail 'missing_dependency' "Install '$commandName' through machine bootstrap." } }
$payloadRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\payloads')).Path
$destination = "${remoteUser}@${targetHost}:"
$sshRouteArgs = @('-p', "$port"); $scpRouteArgs = @('-P', "$port")
if ($proxyJump) { $sshRouteArgs += @('-J', $proxyJump); $scpRouteArgs += @('-o', "ProxyJump=$proxyJump") }
$identityArgs = @('-o', 'IdentityAgent=none', '-o', 'IdentitiesOnly=yes')
$keyName = [IO.Path]::GetFileName($publicKey)
if ($targetOs -eq 'windows') {
    & scp @scpRouteArgs @identityArgs $publicKey (Join-Path $payloadRoot 'authorize-windows.ps1') $destination
    if ($LASTEXITCODE -ne 0) { Fail 'initial_auth_failed' 'Retry interactively with the verified account password.' }
    & ssh @sshRouteArgs @identityArgs "${remoteUser}@${targetHost}" "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\authorize-windows.ps1 '$keyName'"
} else {
    & scp @scpRouteArgs @identityArgs $publicKey (Join-Path $payloadRoot 'authorize-unix.sh') $destination
    if ($LASTEXITCODE -ne 0) { Fail 'initial_auth_failed' 'Retry interactively with the verified account password.' }
    & ssh @sshRouteArgs @identityArgs "${remoteUser}@${targetHost}" "/bin/sh \"`$HOME/authorize-unix.sh\" \"`$HOME/$keyName\""
}
if ($LASTEXITCODE -ne 0) { Fail 'authorization_failed' 'Inspect the target authorized-key path and permissions.' }
Write-Output 'schema_version=1'; Write-Output 'action=apply'; Write-Output 'status=authorized'; Write-Output "transport=$transport"; Write-Output "target=$targetHost"; Write-Output "port=$port"; Write-Output "proxy_jump=$(if ($proxyJump) { $proxyJump } else { 'none' })"; Write-Output "user=$remoteUser"
