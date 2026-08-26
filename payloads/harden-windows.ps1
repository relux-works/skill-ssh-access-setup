$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'administrator privileges required' }
$configPath = Join-Path $env:ProgramData 'ssh\sshd_config'
$backupPath = "$configPath.ssh-access.previous"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "missing sshd configuration: $configPath" }
Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
$begin = '# BEGIN ssh-access managed key-only authentication'
$end = '# END ssh-access managed key-only authentication'
$managedBlock = "$begin`r`nPubkeyAuthentication yes`r`nPasswordAuthentication no`r`n$end`r`n"
$content = Get-Content -LiteralPath $configPath -Raw
$pattern = '(?ms)^# BEGIN ssh-access managed key-only authentication\r?\n.*?^# END ssh-access managed key-only authentication\r?\n?'
$content = [Text.RegularExpressions.Regex]::Replace($content, $pattern, '')
[IO.File]::WriteAllText($configPath, $managedBlock + $content.TrimStart(), [Text.UTF8Encoding]::new($false))
try {
    $sshd = (Get-Command sshd.exe -ErrorAction Stop).Source
    & $sshd -t -f $configPath
    if ($LASTEXITCODE -ne 0) { throw 'sshd configuration validation failed' }
    $effectiveConfig = (& $sshd -T -f $configPath 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $effectiveConfig -notmatch '(?m)^passwordauthentication no\s*$') { throw 'managed authentication policy is not effective' }
    Restart-Service -Name sshd -ErrorAction Stop
} catch {
    Copy-Item -LiteralPath $backupPath -Destination $configPath -Force
    Restart-Service -Name sshd -ErrorAction SilentlyContinue
    throw
}
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
Write-Output 'status=hardened'
Write-Output 'platform=windows'
Write-Output "file=$configPath"
Write-Output "backup=$backupPath"
