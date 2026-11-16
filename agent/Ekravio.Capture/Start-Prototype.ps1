[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GStreamerBin,
    [uri]$WhipEndpoint = 'http://127.0.0.1:8889/stage0/whip',
    [securestring]$PublisherPassword,
    [ValidateSet('Software', 'MediaFoundation')][string]$Encoder = 'Software',
    [ValidateRange(-1, 15)][int]$MonitorIndex = -1,
    [ValidateRange(3, 180)][int]$DurationSeconds = 75,
    [switch]$TestPattern,
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'
if ($ProbeOnly -and $TestPattern) { throw 'Choose either the DXGI probe or the synthetic publisher.' }
if (-not $ProbeOnly -and (-not $WhipEndpoint.IsAbsoluteUri -or $WhipEndpoint.UserInfo -or $WhipEndpoint.Query -or
    $WhipEndpoint.Fragment -or $WhipEndpoint.AbsolutePath -ne '/stage0/whip' -or
    ($WhipEndpoint.Scheme -ne 'https' -and $WhipEndpoint.AbsoluteUri -notmatch '^http://127\.0\.0\.1:\d+/'))) {
    throw 'Use the HTTPS WHIP endpoint for the lab, or HTTP on 127.0.0.1.'
}

$bin = (Get-Item -LiteralPath $GStreamerBin).FullName
$launcher = Join-Path $bin 'gst-launch-1.0.exe'
$inspector = Join-Path $bin 'gst-inspect-1.0.exe'
$frameCount = 10 * $DurationSeconds
if ($TestPattern) {
    $source = @('videotestsrc', 'is-live=true', 'pattern=ball', "num-buffers=$frameCount")
} else {
    if (-not $ProbeOnly -and [Console]::IsInputRedirected) {
        throw 'Start screen capture in a visible interactive console in the Windows user session.'
    }
    $guard = Join-Path $PSScriptRoot 'Ekravio.Capture.exe'
    if (-not (Test-Path -LiteralPath $guard -PathType Leaf)) {
        $guard = Join-Path $PSScriptRoot 'bin/Release/net11.0/Ekravio.Capture.exe'
    }
    if (-not (Test-Path -LiteralPath $guard -PathType Leaf)) {
        throw 'Build the capture guard first: dotnet build agent/Ekravio.Capture -c Release'
    }
    $source = @('d3d11screencapturesrc', 'capture-api=dxgi', 'show-cursor=true',
        "monitor-index=$MonitorIndex", "num-buffers=$frameCount")
}

if ($Encoder -eq 'MediaFoundation') {
    $pixelFormat = 'NV12'
    $coding = @('mfh264enc', 'bitrate=1500', 'bframes=0', 'gop-size=20', 'cabac=false', 'low-latency=true')
} else {
    $pixelFormat = 'I420'
    $coding = @('x264enc', 'bitrate=1500', 'bframes=0', 'key-int-max=20', 'speed-preset=ultrafast', 'tune=zerolatency')
}

$previousPath = $env:PATH
$env:PATH = "$bin;$previousPath"
try {
    $required = @($source[0], 'videoconvert', 'videoscale', $coding[0], 'h264parse')
    if (-not $ProbeOnly) { $required += 'whipclientsink' }
    foreach ($element in $required) {
        & $inspector $element *> $null
        if ($LASTEXITCODE -ne 0) { throw "Missing GStreamer element: $element" }
    }
    $videoPipeline = $source + @('!', 'video/x-raw,framerate=10/1', '!', 'videoconvert', '!',
        'videoscale', 'add-borders=true', '!', "video/x-raw,format=$pixelFormat,width=1280,height=720,pixel-aspect-ratio=1/1") +
        @('!') + $coding + @('!', 'h264parse', 'config-interval=-1', '!', 'video/x-h264,profile=constrained-baseline')
    $deadline = $DurationSeconds + 10
    if ($ProbeOnly) {
        Write-Host "Ekravio Capture | local DXGI probe | $Encoder | frames discarded in memory"
        $pipeline = $videoPipeline + @('!', 'identity', 'name=encoder_output', 'silent=false',
            '!', 'fakesink', 'sync=false', 'enable-last-sample=false')
        $frames = @(& $guard 'probe' $deadline $launcher '-v' @pipeline |
            Select-String -SimpleMatch 'GstIdentity:encoder_output: last-message = chain').Count
        if ($LASTEXITCODE -ne 0 -or $frames -ne $frameCount) {
            throw "DXGI probe returned $frames of $frameCount H.264 frames (exit code $LASTEXITCODE)."
        }
        Write-Host "DXGI probe passed ($frames frames, 1280x720, 10 FPS, H.264)."
        return
    }

    if (-not $PublisherPassword) { $PublisherPassword = Read-Host 'Publisher password' -AsSecureString }
    if ($PublisherPassword.Length -lt 16) { throw 'Enter the publisher password configured on the lab server.' }
    if (-not $TestPattern) {
        Write-Host "This test will share and record one desktop at $WhipEndpoint for about $DurationSeconds seconds. Use a test desktop. Ctrl+C stops capture."
        if ((Read-Host 'Type START to begin recording') -cne 'START') { return }
    }

    $passwordText = [pscredential]::new('publisher', $PublisherPassword).GetNetworkCredential().Password
    if ($passwordText -notmatch '^[A-Za-z0-9_-]+$') { throw 'Use a random publisher password containing letters, digits, underscore or hyphen.' }
    $pipeline = $videoPipeline + @('!', 'whipclientsink', "signaller::whip-endpoint=$WhipEndpoint", 'stun-server=NULL')
    Write-Host "Ekravio Capture | $($source[0]) | $Encoder | Ctrl+C to stop"
    if ($TestPattern) {
        & $launcher '-e' @pipeline "signaller::auth-token=publisher:$passwordText"
    } else {
        $previousSecret = $env:EKRAVIO_CAPTURE_PUBLISHER_PASSWORD
        $env:EKRAVIO_CAPTURE_PUBLISHER_PASSWORD = $passwordText
        try { & $guard 'publish' $deadline $launcher '-e' @pipeline }
        finally { $env:EKRAVIO_CAPTURE_PUBLISHER_PASSWORD = $previousSecret }
    }
    if ($LASTEXITCODE -ne 0) { throw "Capture ended with code $LASTEXITCODE." }
} finally { $env:PATH = $previousPath }
