[CmdletBinding()]
param(
    [string]$DestinationDirectory,
    [switch]$NoClipboard
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-PackageHash([string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Package not found: $Path. Extract the entire ZIP first."
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        throw "Package checksum mismatch: $Path. No installation was attempted. Download the ZIP again."
    }
}

$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
if ($release.archive -notmatch '^ds-bot-[0-9]+\.[0-9]+\.[0-9]+(?:-r[0-9]+)?\.tgz$' -or
    $release.revision -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-r[0-9]+)?$' -or
    $release.sha256 -notmatch '^[a-f0-9]{64}$') {
    throw 'Invalid release metadata. Download the official installer ZIP again.'
}
$source = Join-Path $PSScriptRoot $release.archive
Assert-PackageHash $source $release.sha256

if (-not $DestinationDirectory) {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable. Set -DestinationDirectory explicitly.' }
    $DestinationDirectory = Join-Path $env:LOCALAPPDATA ('DSBot\packages\' + $release.revision)
}
[void](New-Item -ItemType Directory -Path $DestinationDirectory -Force)
$destination = Join-Path (Resolve-Path -LiteralPath $DestinationDirectory).Path $release.archive
if (Test-Path -LiteralPath $destination) {
    # Never replace a file with different bytes behind an existing local lock entry.
    Assert-PackageHash $destination $release.sha256
} else {
    $temporary = $destination + '.' + [guid]::NewGuid().ToString('N') + '.part'
    try {
        Copy-Item -LiteralPath $source -Destination $temporary
        Assert-PackageHash $temporary $release.sha256
        [System.IO.File]::Move($temporary, $destination)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

$spec = 'ds-bot@file:' + $destination.Replace('\', '/')
$instructions = @"
DS Bot $($release.version) - verified local package

Paste the following ONE line into DSH > Plugins > Add plugin, then install and enable:
$spec

Fully quit and reopen DSH after installation.
Keep this package in place: pnpm may need it for later installs or repairs.
This helper only prepares the package. It does not install it, edit DSH files,
delete your data, or turn off integrity checks.
"@
[System.IO.File]::WriteAllText((Join-Path $DestinationDirectory 'INSTALL.txt'), $instructions, [System.Text.UTF8Encoding]::new($true))
if (-not $NoClipboard) {
    try { Set-Clipboard -Value $spec; Write-Host 'Installation text copied to clipboard.' }
    catch { Write-Warning 'Clipboard unavailable. Copy the line below or open INSTALL.txt.' }
}
Write-Host $instructions
