$ErrorActionPreference = 'Stop'
function Fail([string]$Code, [string]$Action) { [Console]::Error.WriteLine("error_code=$Code"); [Console]::Error.WriteLine("action=$Action"); exit 1 }
$aliasName = ''; $targetHost = ''; $remoteUser = ''; $privateKey = ''; $proxyJump = ''; $transport = 'direct'; $port = 22; $apply = $false
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--alias' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --alias.' }; $aliasName = $args[$index] }
        '--host' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --host.' }; $targetHost = $args[$index] }
        '--user' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --user.' }; $remoteUser = $args[$index] }
        '--key' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --key.' }; $privateKey = $args[$index] }
        '--port' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --port.' }; $port = $args[$index] }
        '--proxy-jump' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --proxy-jump.' }; $proxyJump = $args[$index] }
        '--transport' { if (++$index -ge $args.Count) { Fail 'invalid_arguments' 'Provide a value after --transport.' }; $transport = $args[$index] }
        '--apply' { $apply = $true }
        default { Fail 'invalid_arguments' 'Use alias, endpoint, account, key, and optional route arguments.' }
    }
}
if (-not ($aliasName -and $targetHost -and $remoteUser -and $privateKey)) { Fail 'invalid_arguments' 'Provide every required value.' }
if ($aliasName -notmatch '^[A-Za-z0-9._-]+$') { Fail 'invalid_alias' 'Use letters, digits, dots, underscores, or hyphens.' }
if ($targetHost -notmatch '^[A-Za-z0-9._:%-]+$') { Fail 'invalid_host' 'Use a valid hostname, IPv4 address, or IPv6 address.' }
if ($remoteUser -notmatch '^[A-Za-z0-9._@\\-]+$') { Fail 'invalid_user' 'Use the verified remote account name.' }
if ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { Fail 'invalid_port' 'Use a TCP port from 1 through 65535.' }
if ($transport -notmatch '^[A-Za-z0-9._-]+$') { Fail 'invalid_transport' 'Use a short transport label without spaces.' }
if ($proxyJump -and $proxyJump -match '[\s#]') { Fail 'invalid_proxy_jump' 'Use an SSH alias or a compact OpenSSH jump specification.' }
if (-not (Test-Path -LiteralPath $privateKey -PathType Leaf)) { Fail 'missing_private_key' 'Select an existing local private key.' }
$sshDirectory = Join-Path $HOME '.ssh'; $configFile = Join-Path $sshDirectory 'config'
$exists = $false
if (Test-Path $configFile) { foreach ($line in Get-Content -LiteralPath $configFile) { if ($line -match '^\s*Host\s+(.+)$' -and (($Matches[1] -split '\s+') -contains $aliasName)) { $exists = $true; break } } }
$action = if ($apply) { 'apply' } else { 'preview' }
if ($exists) { Write-Output 'schema_version=1'; Write-Output "action=$action"; Write-Output 'status=already_exists'; Write-Output "alias=$aliasName"; Write-Output "config=$configFile"; exit 0 }
function Write-Status([string]$Action, [string]$Status) { Write-Output 'schema_version=1'; Write-Output "action=$Action"; Write-Output "status=$Status"; Write-Output "alias=$aliasName"; Write-Output "transport=$transport"; Write-Output "host=$targetHost"; Write-Output "port=$port"; Write-Output "proxy_jump=$(if ($proxyJump) { $proxyJump } else { 'none' })"; Write-Output "user=$remoteUser"; Write-Output "key=$privateKey"; Write-Output "config=$configFile" }
if (-not $apply) { Write-Status 'preview' 'would_add'; exit 0 }
New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
$block = "`r`nHost $aliasName`r`n  HostName $targetHost`r`n  Port $port`r`n  User $remoteUser`r`n  IdentityFile `"$privateKey`"`r`n  IdentitiesOnly yes`r`n"
if ($proxyJump) { $block += "  ProxyJump $proxyJump`r`n" }
[IO.File]::AppendAllText($configFile, $block, [Text.UTF8Encoding]::new($false))
Write-Status 'apply' 'added'
