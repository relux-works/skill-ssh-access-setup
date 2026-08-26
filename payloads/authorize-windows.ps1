$ErrorActionPreference = 'Stop'
$publicKeyName = $args[0]
if (-not $publicKeyName) { throw 'public key filename required' }
$publicKeyPath = Join-Path $HOME $publicKeyName
$publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
if (-not $publicKey) { throw 'public key is empty' }
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdministrator) {
    $destination = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
} else {
    $sshDirectory = Join-Path $HOME '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
    $destination = Join-Path $sshDirectory 'authorized_keys'
}
$existing = if (Test-Path $destination) { @(Get-Content -LiteralPath $destination) } else { @() }
if ($existing -notcontains $publicKey) { [IO.File]::AppendAllText($destination, "$publicKey`r`n", [Text.UTF8Encoding]::new($false)) }
if ($isAdministrator) {
    & icacls.exe $destination /inheritance:r /grant 'BUILTIN\Administrators:F' /grant 'NT AUTHORITY\SYSTEM:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'failed to secure administrators_authorized_keys ACL' }
}
Remove-Item -LiteralPath $publicKeyPath, $PSCommandPath -Force -ErrorAction SilentlyContinue
Write-Output 'status=authorized'
Write-Output "authorized_keys=$destination"
