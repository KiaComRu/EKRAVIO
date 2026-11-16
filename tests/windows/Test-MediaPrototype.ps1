[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MediaMtx,
    [Parameter(Mandatory)][string]$GStreamerBin,
    [ValidateSet('Software', 'MediaFoundation')][string]$Encoder = 'Software',
    [ValidateRange(15, 180)][int]$DurationSeconds = 75,
    [ValidateRange(1024, 65535)][int]$WebRtcPort = 18889,
    [ValidateRange(1024, 65535)][int]$IcePort = 18189,
    [ValidateRange(1024, 65535)][int]$PlaybackPort = 19996
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$mediaBinary = (Get-Item -LiteralPath $MediaMtx).FullName
$bin = (Get-Item -LiteralPath $GStreamerBin).FullName
$runPath = Join-Path $root ('.stage0/media-test-' + [guid]::NewGuid().ToString('N'))
$publisherText = [guid]::NewGuid().ToString('N')
$viewerText = [guid]::NewGuid().ToString('N')
$publisher = ConvertTo-SecureString $publisherText -AsPlainText -Force
$viewer = ConvertTo-SecureString $viewerText -AsPlainText -Force
$null = & (Join-Path $root 'deploy/mediamtx/Start-Prototype.ps1') -MediaMtx $mediaBinary `
    -RunDirectory $runPath -PublisherPassword $publisher -ViewerPassword $viewer -ConfigureOnly `
    -WebRtcPort $WebRtcPort -IcePort $IcePort -PlaybackPort $PlaybackPort
Add-Type -AssemblyName System.Net.Http
$http = [Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromSeconds(8)
function Get-Status([uri]$Uri, [hashtable]$Headers = @{}) {
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Uri)
    try {
        foreach ($key in $Headers.Keys) { $request.Headers.Add($key, $Headers[$key]) }
        $result = $http.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try { [int]$result.StatusCode } finally { $result.Dispose() }
    } finally { $request.Dispose() }
}

$publishOrigin = "http://127.0.0.1:$WebRtcPort"
$playbackOrigin = "http://127.0.0.1:$PlaybackPort"
$listUrl = "$playbackOrigin/list?path=stage0"
$viewerHeaders = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("viewer:$viewerText")) }
$publisherHeaders = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("publisher:$publisherText")) }
$logs = Join-Path $runPath 'media.log'
$server = Start-Process -FilePath $mediaBinary -ArgumentList 'mediamtx.yml' -WorkingDirectory $runPath `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput $logs -RedirectStandardError (Join-Path $runPath 'error.log')
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        if ($server.HasExited) { throw "MediaMTX failed to start. See $logs" }
        $status = try { Get-Status $listUrl } catch { 0 }
        if ($status -ne 0) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if ($status -ne 401) { throw "Anonymous playback returned $status. Expected 401." }
    if ((Get-Status "$publishOrigin/stage0/") -ne 401) { throw 'Anonymous live page access was not denied.' }
    $publisherStatus = Get-Status $listUrl $publisherHeaders
    if ($publisherStatus -ne 401) { throw "Publisher playback returned $publisherStatus. Expected 401." }
    $liveStatus = Get-Status "$publishOrigin/stage0/" $viewerHeaders
    if ($liveStatus -ne 200) { throw "The live page returned $liveStatus. Expected 200." }

    & (Join-Path $root 'agent/Ekravio.Capture/Start-Prototype.ps1') -GStreamerBin $bin `
        -WhipEndpoint "$publishOrigin/stage0/whip" -PublisherPassword $publisher -TestPattern `
        -DurationSeconds $DurationSeconds -Encoder $Encoder

    $archive = @(Invoke-RestMethod $listUrl -Headers $viewerHeaders -TimeoutSec 5)
    $longest = $archive | Sort-Object duration -Descending | Select-Object -First 1
    # The finite source starts before ICE and the first decodable key frame.
    $expected = [Math]::Min($DurationSeconds - 8, 60)
    if (-not $longest -or $longest.duration -lt $expected) { throw "No archive interval of at least $expected seconds." }
    $archiveUrl = [uri]$longest.url
    if ($archiveUrl.GetLeftPart([UriPartial]::Authority) -ne $playbackOrigin) { throw 'Unexpected playback host.' }

    $download = Join-Path $runPath 'playback.mp4'
    $segment = Invoke-WebRequest $archiveUrl -Headers $viewerHeaders -UseBasicParsing -TimeoutSec 15 `
        -OutFile $download -PassThru
    if ($segment.StatusCode -ne 200 -or (Get-Item -LiteralPath $download).Length -lt 1024) {
        throw 'Recorded MP4 could not be fetched.'
    }
    if (-not (Get-ChildItem -LiteralPath (Join-Path $runPath 'recordings/stage0') -Filter '*.mp4')) {
        throw 'No server-side MP4 segment was written.'
    }
    $previousPath = $env:PATH
    $env:PATH = "$bin;$previousPath"
    try {
        $mediaFile = $download.Replace('\', '/')
        $frames = @(& (Join-Path $bin 'gst-launch-1.0.exe') '-v' 'filesrc' "location=$mediaFile" `
            '!' 'qtdemux' '!' 'h264parse' '!' 'avdec_h264' '!' 'identity' 'name=decoded' 'silent=false' `
            '!' 'fakesink' 'sync=false' | Select-String -SimpleMatch 'GstIdentity:decoded: last-message = chain').Count
        if ($LASTEXITCODE -ne 0 -or $frames -lt ($expected * 10)) {
            throw "The archived MP4 decoded $frames frames. Expected at least $($expected * 10)."
        }
    } finally { $env:PATH = $previousPath }
    Write-Host "Synthetic WHIP, recording and decoding passed ($($longest.duration) s, $frames frames). Artifacts: $runPath"
} finally {
    $http.Dispose()
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -ErrorAction SilentlyContinue }
    $server.Dispose()
}
