[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MediaMtx,
    [string]$RunDirectory = (Join-Path $PSScriptRoot '../../.stage0/server'),
    [ipaddress]$BindAddress = '127.0.0.1',
    [string]$ServerName,
    [string]$Certificate,
    [string]$CertificateKey,
    [ValidateRange(1024, 65535)][int]$WebRtcPort = 8889,
    [ValidateRange(1024, 65535)][int]$IcePort = 8189,
    [ValidateRange(1024, 65535)][int]$PlaybackPort = 9996,
    [securestring]$PublisherPassword,
    [securestring]$ViewerPassword,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = 'Stop'
if ($BindAddress.AddressFamily -ne 'InterNetwork' -or $BindAddress.Equals([ipaddress]::Any)) {
    throw 'Choose a specific IPv4 address.'
}
if (-not $ServerName) { $ServerName = $BindAddress.ToString() }
if ([Uri]::CheckHostName($ServerName) -notin @('Dns', 'IPv4')) { throw 'Invalid server name.' }
$useTls = [bool]($Certificate -and $CertificateKey)
if (([bool]$Certificate -ne [bool]$CertificateKey) -or
    (-not [ipaddress]::IsLoopback($BindAddress) -and -not $useTls)) {
    throw 'Supply both the PEM certificate and key. HTTPS is required for LAN runs.'
}
if (Get-ChildItem Env:MTX_*) { throw 'Clear inherited MTX_* configuration overrides before starting the lab.' }

$mediaBinary = (Get-Item -LiteralPath $MediaMtx).FullName
if ((& $mediaBinary --version) -ne 'v1.21.3' -or $LASTEXITCODE -ne 0) { throw 'Use MediaMTX v1.21.3.' }
if (-not $PublisherPassword) { $PublisherPassword = Read-Host 'Publisher password' -AsSecureString }
if (-not $ViewerPassword) { $ViewerPassword = Read-Host 'Viewer password' -AsSecureString }

function Get-PasswordHash([securestring]$Password) {
    if ($Password.Length -lt 16) { throw 'Use a random password of at least 16 characters.' }
    $passwordText = [pscredential]::new('unused', $Password).GetNetworkCredential().Password
    $bytes = [Text.Encoding]::UTF8.GetBytes($passwordText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { 'sha256:' + [Convert]::ToBase64String($sha.ComputeHash($bytes)) }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
        $sha.Dispose()
    }
}

$publisherHash = Get-PasswordHash $PublisherPassword
$viewerHash = Get-PasswordHash $ViewerPassword
if ($publisherHash -eq $viewerHash) { throw 'Use different passwords for publisher and viewer.' }

$scheme = if ($useTls) { 'https' } else { 'http' }
$origin = "${scheme}://${ServerName}:${WebRtcPort}"
$playbackOrigin = "${scheme}://${ServerName}:${PlaybackPort}"
$configuration = @{
    authMethod = 'internal'
    authInternalUsers = @(
        @{ user = 'publisher'; pass = $publisherHash; permissions = @(@{ action = 'publish'; path = 'stage0' }) },
        @{ user = 'viewer'; pass = $viewerHash; permissions = @(
            @{ action = 'read'; path = 'stage0' }, @{ action = 'playback'; path = 'stage0' }
        ) }
    )
    rtsp = $false
    rtmp = $false
    hls = $false
    srt = $false
    moq = $false
    webrtc = $true
    webrtcAddress = "${BindAddress}:${WebRtcPort}"
    webrtcLocalUDPAddress = "${BindAddress}:${IcePort}"
    webrtcIPsFromInterfaces = $false
    webrtcAdditionalHosts = @($BindAddress.ToString())
    webrtcAllowOrigins = @($origin)
    playback = $true
    playbackAddress = "${BindAddress}:${PlaybackPort}"
    playbackAllowOrigins = @($playbackOrigin)
    paths = @{
        stage0 = @{
            source = 'publisher'
            overridePublisher = $false
            record = $true
            recordPath = './recordings/%path/%Y-%m-%d_%H-%M-%S-%f_%z'
            recordFormat = 'fmp4'
            recordPartDuration = '1s'
            recordSegmentDuration = '1m'
            recordDeleteAfter = '1h'
        }
    }
}
if ($useTls) {
    $configuration.webrtcEncryption = $true
    $configuration.webrtcServerCert = (Get-Item -LiteralPath $Certificate).FullName
    $configuration.webrtcServerKey = (Get-Item -LiteralPath $CertificateKey).FullName
    $configuration.playbackEncryption = $true
    $configuration.playbackServerCert = $configuration.webrtcServerCert
    $configuration.playbackServerKey = $configuration.webrtcServerKey
}

$runPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDirectory)
[IO.Directory]::CreateDirectory($runPath) | Out-Null
$configPath = Join-Path $runPath 'mediamtx.yml'
$file = [IO.File]::Open($configPath, [IO.FileMode]::CreateNew)
try {
    $configBytes = [Text.Encoding]::UTF8.GetBytes(($configuration | ConvertTo-Json -Depth 8))
    $file.Write($configBytes, 0, $configBytes.Length)
} finally { $file.Dispose() }
if ($ConfigureOnly) { return $configPath }

Write-Host "Publisher WHIP: $origin/stage0/whip"
Write-Host "Live (viewer): $origin/stage0/"
Write-Host "Archive (viewer): $playbackOrigin/list?path=stage0"
Write-Host "Recordings: $(Join-Path $runPath 'recordings')"
Push-Location -LiteralPath $runPath
try {
    & $mediaBinary $configPath
    if ($LASTEXITCODE -ne 0) { throw "MediaMTX exited with code $LASTEXITCODE." }
} finally { Pop-Location }
