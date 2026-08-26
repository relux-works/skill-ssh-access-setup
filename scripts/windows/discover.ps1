$ErrorActionPreference = 'Stop'
function Fail([string]$Code, [string]$Action) { [Console]::Error.WriteLine("error_code=$Code"); [Console]::Error.WriteLine("action=$Action"); exit 1 }
if ($args.Count -ne 0) { Fail 'invalid_arguments' 'Run ssh-access-discover without arguments.' }
if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { Fail 'missing_dependency' "Install or enable 'ssh-keygen' through machine bootstrap." }

Write-Output "record`ttransport`tendpoint`tname`towner`tos`tstate`tpath`tdetails"
Write-Output "adapter`tdirect`t-`t-`t-`t-`tavailable`t-`tuser_supplied_endpoint"
$sshDirectory = Join-Path $HOME '.ssh'; $sshConfig = Join-Path $sshDirectory 'config'
if (Test-Path -LiteralPath $sshConfig) {
    Write-Output "adapter`tssh-config`t-`t-`t-`t-`tavailable`t$sshConfig`texisting_aliases"
    $routes = @()
    foreach ($line in Get-Content -LiteralPath $sshConfig) {
        if ($line -match '^\s*Host\s+(.+)$') {
            foreach ($name in ($Matches[1] -split '\s+')) {
                if ($name -notmatch '[*?!\[\]]') { $routes += "route`tssh-config`t$name`t$name`t-`t-`tconfigured`t-`talias" }
            }
        }
    }
    $routes | Sort-Object | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "adapter`tssh-config`t-`t-`t-`t-`tunconfigured`t$sshConfig`tno_config"
}

if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    $statusOutput = @(& tailscale status 2>$null)
    if ($LASTEXITCODE -eq 0) {
        Write-Output "adapter`ttailscale`t-`t-`t-`t-`tavailable`t-`tpeer_discovery"
        $peers = @()
        foreach ($line in $statusOutput) {
            $fields = $line.Trim() -split '\s+', 5
            if ($fields.Count -lt 4 -or $fields[3] -notmatch '^(?i:macOS|linux|windows)$') { continue }
            $state = 'available'
            if ($fields.Count -ge 5 -and $fields[4] -match 'offline') { $state = 'offline' }
            elseif ($fields.Count -ge 5 -and $fields[4] -match 'idle') { $state = 'idle' }
            elseif ($fields.Count -ge 5 -and $fields[4] -match 'active') { $state = 'active' }
            $peers += "route`ttailscale`t$($fields[0])`t$($fields[1])`t$($fields[2])`t$($fields[3])`t$state`t-`tpeer"
        }
        $peers | Sort-Object | ForEach-Object { Write-Output $_ }
    } else { Write-Output "adapter`ttailscale`t-`t-`t-`t-`tunavailable`t-`tnot_authenticated" }
}
if (Get-Command zerotier-cli -ErrorAction SilentlyContinue) { Write-Output "adapter`tzerotier`t-`t-`t-`t-`tavailable`t-`tmanual_endpoint_required" }
if (Get-Command wg -ErrorAction SilentlyContinue) { Write-Output "adapter`twireguard`t-`t-`t-`t-`tavailable`t-`tmanual_endpoint_required" }

if (Test-Path $sshDirectory) {
    Get-ChildItem -LiteralPath $sshDirectory -Filter '*.pub' -File | Sort-Object FullName | ForEach-Object {
        $fingerprint = (& ssh-keygen -lf $_.FullName 2>&1)
        if ($LASTEXITCODE -ne 0) { Fail 'invalid_public_key' "Inspect or replace the public key at $($_.FullName)." }
        Write-Output "key`tlocal`t-`t-`t-`t-`tavailable`t$($_.FullName)`t$fingerprint"
    }
}
