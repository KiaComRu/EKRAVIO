[CmdletBinding()]
param(
    [switch]$ProbeOnly,
    [string]$GStreamerBin,
    [uri]$WhipEndpoint
)

$ErrorActionPreference = 'Stop'
try {
    if (-not $GStreamerBin) {
        $roots = @($env:GSTREAMER_1_0_ROOT_MSVC_X86_64,
            (Join-Path $env:ProgramFiles 'gstreamer/1.0/msvc_x86_64'),
            (Join-Path $env:LOCALAPPDATA 'Programs/gstreamer/1.0/msvc_x86_64'),
            'C:/gstreamer/1.0/msvc_x86_64')
        foreach ($root in $roots) {
            if ($root -and (Test-Path -LiteralPath (Join-Path $root 'bin/gst-launch-1.0.exe') -PathType Leaf)) {
                $GStreamerBin = Join-Path $root 'bin'
                break
            }
        }
    }
    if (-not $GStreamerBin) {
        Write-Host 'Install GStreamer 1.28.7 MSVC x64 with the x264, D3D11 and WebRTC plugins.'
        $GStreamerBin = (Read-Host 'Path to the GStreamer bin directory').Trim('"')
        if (-not $GStreamerBin) { return }
    }

    $options = @{ GStreamerBin = $GStreamerBin }
    if ($ProbeOnly) {
        $options.ProbeOnly = $true
        $options.DurationSeconds = 5
    } else {
        if (-not $WhipEndpoint) {
            $address = Read-Host 'Server WHIP URL (Enter for http://127.0.0.1:8889/stage0/whip)'
            if ($address) { $WhipEndpoint = $address }
        }
        if ($WhipEndpoint) { $options.WhipEndpoint = $WhipEndpoint }
    }
    & (Join-Path $PSScriptRoot 'Start-Prototype.ps1') @options
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}
Read-Host 'Press Enter to close' | Out-Null
