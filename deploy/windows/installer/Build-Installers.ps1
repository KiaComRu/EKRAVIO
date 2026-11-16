[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InnoCompiler,
    [Parameter(Mandatory)][string]$MediaMtxDirectory,
    [Parameter(Mandatory)][string]$WinSW,
    [Parameter(Mandatory)][string]$WinSWLicense,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../../dist/windows')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$compiler = (Get-Item -LiteralPath $InnoCompiler).FullName
$mediaDirectory = (Get-Item -LiteralPath $MediaMtxDirectory).FullName
$serviceWrapper = (Get-Item -LiteralPath $WinSW).FullName
$wrapperLicense = (Get-Item -LiteralPath $WinSWLicense).FullName
$mediaBinary = Join-Path $mediaDirectory 'mediamtx.exe'

function Confirm-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "Unexpected SHA-256 for $Path. Use the pinned upstream artifact."
    }
}

# MediaMTX v1.21.3 Windows amd64 and WinSW v2.12.0 .NET Framework 4.6.1.
Confirm-Hash $mediaBinary '13A0BFAA852D83CE976C94342A1AF130941BD79FAC2C1E95A2175879C92304C0'
Confirm-Hash $serviceWrapper 'B5066B7BBDFBA1293E5D15CDA3CAAEA88FBEAB35BD5B38C41C913D492AADFC4F'
Confirm-Hash $wrapperLicense '1CDF703C10A70E5973BF3ACF2A5EEABE7746237155B92DB2034AEAE26FDF7802'

$stage = Join-Path $root ('.stage0/installer-build-' + [guid]::NewGuid().ToString('N'))
$agent = Join-Path $stage 'agent'
$server = Join-Path $stage 'server'
$packages = Join-Path $stage 'packages'
foreach ($directory in @($agent, $server, $packages)) { [IO.Directory]::CreateDirectory($directory) | Out-Null }

foreach ($project in @('Ekravio.Capture','Ekravio.SessionMonitor')) {
    $projectFile = Join-Path $root "agent/$project/$project.csproj"
    & dotnet publish $projectFile -c Release -r win-x64 --self-contained true -p:DebugType=None -o $agent
    if ($LASTEXITCODE -ne 0) { throw "Publishing $project failed ($LASTEXITCODE)." }
}

$runtimeConfig = Get-Content -LiteralPath (Join-Path $agent 'Ekravio.Capture.runtimeconfig.json') -Raw | ConvertFrom-Json
$runtime = $runtimeConfig.runtimeOptions.includedFrameworks | Where-Object name -eq 'Microsoft.NETCore.App'
$assets = Get-Content -LiteralPath (Join-Path $root 'agent/Ekravio.Capture/obj/project.assets.json') -Raw | ConvertFrom-Json
$runtimePackage = foreach ($folder in $assets.packageFolders.PSObject.Properties.Name) {
    $path = Join-Path $folder "microsoft.netcore.app.runtime.win-x64/$($runtime.version)"
    if (Test-Path -LiteralPath (Join-Path $path 'THIRD-PARTY-NOTICES.TXT') -PathType Leaf) {
        $path
        break
    }
}
if (-not $runtimePackage) { throw 'The license files for the bundled .NET runtime were not found.' }
Copy-Item -LiteralPath (Join-Path $runtimePackage 'LICENSE.TXT') -Destination (Join-Path $agent 'DotNet-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $runtimePackage 'THIRD-PARTY-NOTICES.TXT') -Destination (Join-Path $agent 'DotNet-THIRD-PARTY-NOTICES.txt')

Copy-Item -LiteralPath (Join-Path $root 'agent/Ekravio.Capture/Start-Prototype.ps1') -Destination $agent
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Agent-Launcher.ps1') -Destination $agent
Copy-Item -LiteralPath (Join-Path $root 'brand/ekravio-symbol.ico') -Destination (Join-Path $stage 'ekravio.ico')

Copy-Item -LiteralPath $mediaBinary -Destination $server
Copy-Item -LiteralPath (Join-Path $mediaDirectory 'LICENSE') -Destination (Join-Path $server 'MediaMTX-LICENSE.txt')
Copy-Item -LiteralPath $serviceWrapper -Destination (Join-Path $server 'Ekravio.Media.exe')
Copy-Item -LiteralPath $wrapperLicense -Destination (Join-Path $server 'WinSW-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $root 'deploy/mediamtx/Start-Prototype.ps1') -Destination $server
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Server-Manager.ps1'),(Join-Path $PSScriptRoot 'Ekravio.Media.xml') -Destination $server
foreach ($directory in @($agent,$server)) {
    # Include a BOM so Windows Notepad opens the Russian instructions as UTF-8.
    $instructions = Get-Content -LiteralPath (Join-Path $root 'docs/install-windows.md') -Raw -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $directory 'Instructions.txt'), $instructions, [Text.UTF8Encoding]::new($true))
}

foreach ($component in @('Agent','Server')) {
    $definition = Join-Path $PSScriptRoot "$component.iss"
    & $compiler '/Qp' "/DStageDir=$stage" "/DPackageDir=$packages" $definition
    if ($LASTEXITCODE -ne 0) { throw "Compiling the $component installer failed ($LASTEXITCODE)." }
}

$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$checksum = foreach ($component in @('Agent','Server')) {
    $name = "Ekravio-$component-Setup-x64.exe"
    $artifact = Join-Path $output $name
    Copy-Item -LiteralPath (Join-Path $packages $name) -Destination $artifact -Force
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $name"
}
[IO.File]::WriteAllLines((Join-Path $output 'SHA256SUMS.txt'), [string[]]$checksum)
Get-ChildItem -LiteralPath $output -Filter 'Ekravio-*-Setup-x64.exe' | Select-Object Name,Length,FullName
