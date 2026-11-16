[CmdletBinding()]
param(
    [ValidateSet('Configure', 'Stop', 'Remove')][string]$Action = 'Configure',
    [ipaddress]$BindAddress = '127.0.0.1',
    [string]$ServerName,
    [string]$Certificate,
    [string]$CertificateKey
)

$ErrorActionPreference = 'Stop'
$serviceName = 'Ekravio.Media'
$wrapper = Join-Path $PSScriptRoot "$serviceName.exe"
$root = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Ekravio/Server'
$config = Join-Path $root 'mediamtx.yml'
$networkOptionsProvided = $PSBoundParameters.ContainsKey('BindAddress') -or $ServerName -or $Certificate -or $CertificateKey

function Get-OwnedService {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) { return }
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
    $image = (Get-ItemPropertyValue -LiteralPath $key -Name ImagePath).Trim('"')
    if ($image -ne $wrapper) { throw "Service $serviceName is registered to another installation." }
    $service
}

function Invoke-WinSW([string]$Command) {
    & $wrapper $Command
    if ($LASTEXITCODE -ne 0) { throw "WinSW $Command failed ($LASTEXITCODE)." }
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ($Action -ne 'Configure' -or $networkOptionsProvided) { throw 'Run this command in an elevated Windows PowerShell.' }
        $arguments = '-NoProfile -ExecutionPolicy RemoteSigned -File "{0}"' -f $PSCommandPath
        $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $elevated = Start-Process -FilePath $powershell -ArgumentList $arguments `
            -Verb RunAs -WindowStyle Normal -Wait -PassThru
        exit $elevated.ExitCode
    }

    $service = Get-OwnedService
    if ($Action -ne 'Configure') {
        if ($service -and $service.Status -ne 'Stopped') {
            Stop-Service -InputObject $service
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        }
        if ($service -and $Action -eq 'Remove') { Invoke-WinSW 'uninstall' }
        return
    }

    foreach ($path in @((Split-Path -Parent $root), $root)) {
        $directory = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($directory -and ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Choose a local directory for the server data: $path"
        }
    }
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $identityRules = @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-19', 'Modify'))
    foreach ($identityRule in $identityRules) {
        $sid = [Security.Principal.SecurityIdentifier]::new($identityRule[0])
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, $identityRule[1],
            'ContainerInherit, ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $root -AclObject $acl

    if (Test-Path -LiteralPath $config -PathType Leaf) {
        if ($networkOptionsProvided) { throw 'The server already has a configuration. Stop it and back up mediamtx.yml before reconfiguring.' }
    } else {
        $options = @{ BindAddress = $BindAddress; ServerName = $ServerName }
        if ($Certificate -or $CertificateKey) {
            if (-not $Certificate -or -not $CertificateKey) { throw 'Provide both the PEM certificate and its key.' }
            $certificateFile = (Get-Item -LiteralPath $Certificate).FullName
            $keyFile = (Get-Item -LiteralPath $CertificateKey).FullName
            $options.Certificate = Join-Path $root 'server.crt'
            $options.CertificateKey = Join-Path $root 'server.key'
            if ($certificateFile -ne $options.Certificate) { Copy-Item -LiteralPath $certificateFile -Destination $options.Certificate }
            if ($keyFile -ne $options.CertificateKey) { Copy-Item -LiteralPath $keyFile -Destination $options.CertificateKey }
        }
        Write-Host 'Choose two different passwords, at least 16 characters each.'
        Write-Host 'Use letters, digits, hyphens and underscores for the publisher password.'
        $null = & (Join-Path $PSScriptRoot 'Start-Prototype.ps1') -MediaMtx (Join-Path $PSScriptRoot 'mediamtx.exe') `
            -RunDirectory $root -ConfigureOnly @options
    }
    if (-not $service) { Invoke-WinSW 'install' }
    Start-Service -Name $serviceName
    $service = Get-OwnedService
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-Host "Ekravio Media service is running. Data and logs: $root"
    $settings = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Live (viewer): $($settings.webrtcAllowOrigins[0])/stage0/"
    Write-Host "Archive (viewer): $($settings.playbackAllowOrigins[0])/list?path=stage0"
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($Action -eq 'Configure') { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
Read-Host 'Press Enter to close' | Out-Null
