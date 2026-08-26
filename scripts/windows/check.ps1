$ErrorActionPreference = 'Stop'
function Fail([string]$Code, [string]$Action) { [Console]::Error.WriteLine("error_code=$Code"); [Console]::Error.WriteLine("action=$Action"); exit 1 }

$targetHost = ''; $remoteUser = ''; $privateKey = ''; $sshAlias = ''; $proxyJump = ''; $transport = 'direct'; $port = 22
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--host' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --host.' }; $targetHost = $args[$index] }
        '--user' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --user.' }; $remoteUser = $args[$index] }
        '--key' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --key.' }; $privateKey = $args[$index] }
        '--alias' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --alias.' }; $sshAlias = $args[$index] }
        '--port' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --port.' }; $port = $args[$index] }
        '--proxy-jump' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --proxy-jump.' }; $proxyJump = $args[$index] }
        '--transport' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --transport.' }; $transport = $args[$index] }
        default { Fail 'invalid_arguments' 'Use --alias NAME or --host HOST --user USER --key PRIVATE_KEY with optional route arguments.' }
    }
}
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Fail 'missing_dependency' "Install 'ssh' through machine bootstrap." }
if ($sshAlias) {
    if ($targetHost -or $remoteUser -or $privateKey -or $proxyJump -or $port -ne 22 -or $transport -ne 'direct') { Fail 'invalid_arguments' 'Do not combine --alias with endpoint or route arguments.' }
    $effective = (& ssh -G $sshAlias 2>$null)
    if ($LASTEXITCODE -ne 0) { Fail 'invalid_alias' "Inspect the SSH config entry for '$sshAlias'." }
    foreach ($line in $effective) {
        $parts = $line -split '\s+', 2
        if ($parts[0] -eq 'hostname') { $targetHost = $parts[1] }
        elseif ($parts[0] -eq 'user') { $remoteUser = $parts[1] }
        elseif ($parts[0] -eq 'identityfile' -and -not $privateKey) { $privateKey = $parts[1] }
        elseif ($parts[0] -eq 'port') { $port = [int]$parts[1] }
        elseif ($parts[0] -eq 'proxyjump' -and $parts[1] -ne 'none') { $proxyJump = $parts[1] }
    }
    $transport = 'ssh-config'
    if ($privateKey.StartsWith('~/')) { $privateKey = Join-Path $HOME $privateKey.Substring(2) }
} elseif (-not ($targetHost -and $remoteUser -and $privateKey)) { Fail 'invalid_arguments' 'Provide --host HOST --user USER --key PRIVATE_KEY.' }
if ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { Fail 'invalid_port' 'Use a TCP port from 1 through 65535.' }
if ($targetHost -notmatch '^[A-Za-z0-9._:%-]+$') { Fail 'invalid_host' 'Use a valid hostname, IPv4 address, or IPv6 address.' }
if ($remoteUser -notmatch '^[A-Za-z0-9._@\\-]+$') { Fail 'invalid_user' 'Use the verified remote account name.' }
if ($transport -notmatch '^[A-Za-z0-9._-]+$') { Fail 'invalid_transport' 'Use a short transport label without spaces.' }
if ($proxyJump -and $proxyJump -match '[\s#]') { Fail 'invalid_proxy_jump' 'Use an SSH alias or a compact OpenSSH jump specification.' }
if (-not (Test-Path -LiteralPath $privateKey -PathType Leaf)) { Fail 'missing_private_key' 'Select an existing local private key.' }

Write-Output 'schema_version=1'; Write-Output "transport=$transport"; Write-Output "target=$targetHost"; Write-Output "port=$port"; Write-Output "proxy_jump=$(if ($proxyJump) { $proxyJump } else { 'none' })"; Write-Output "user=$remoteUser"; Write-Output "key=$privateKey"
if ($proxyJump) { Write-Output 'ssh_port=proxied' }
else {
    $client = [Net.Sockets.TcpClient]::new()
    try { $connected = $client.ConnectAsync($targetHost, [int]$port).Wait(5000) -and $client.Connected } catch { $connected = $false } finally { $client.Dispose() }
    if (-not $connected) { Write-Output 'ssh_port=closed'; Write-Output 'key_auth=not_checked'; Write-Output 'password_auth=not_checked'; exit 0 }
    Write-Output 'ssh_port=open'
}
$target = if ($sshAlias) { $sshAlias } else { "$remoteUser@$targetHost" }
$routeArgs = if ($sshAlias) { @() } elseif ($proxyJump) { @('-p', "$port", '-J', $proxyJump) } else { @('-p', "$port") }
$identityArgs = if ($sshAlias) { @() } else { @('-o', 'IdentitiesOnly=yes', '-i', $privateKey) }
& ssh @routeArgs -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new @identityArgs $target 'exit 0' 2>$null
if ($LASTEXITCODE -eq 0) { Write-Output 'key_auth=ok' } else { Write-Output 'key_auth=missing' }
$authenticationOutput = (& ssh -vv @routeArgs -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive @identityArgs $target 'exit 0' 2>&1 | Out-String)
if ($authenticationOutput -match 'Authentications that can continue:.*(password|keyboard-interactive)') { Write-Output 'password_auth=enabled' }
elseif ($authenticationOutput -match 'Authentications that can continue:.*publickey') { Write-Output 'password_auth=disabled' }
else { Write-Output 'password_auth=unknown' }
