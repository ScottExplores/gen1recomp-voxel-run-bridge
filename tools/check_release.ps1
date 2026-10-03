# Validate the actual updater artifact, not a folder containing local saves/cache.
# This does not replace gameplay tests or assert a complete copyright audit.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ArchivePath,
  [Parameter(Mandatory = $true)][string]$Version
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$releasePath = (Resolve-Path -LiteralPath $ArchivePath).Path
$expectedName = "voxel_run_bridge-$Version.zip"
if ([IO.Path]::GetFileName($releasePath) -cne $expectedName) {
  throw "Updater expects the asset name $expectedName"
}
$archive = [IO.Compression.ZipFile]::OpenRead($releasePath)
try {
  $entries = @{}
  $caseNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($entry in $archive.Entries) {
    $name = $entry.FullName
    if ($name.Contains('\') -or $name.StartsWith('/') -or
        $name -match '(^|/)\.\.(/|$)' -or $name.Contains(':')) {
      throw "Unsafe archive path: $name"
    }
    if (-not $caseNames.Add($name) -or $entries.ContainsKey($name)) {
      throw "Duplicate or case-colliding archive path: $name"
    }
    $entries[$name] = $entry
    if ($name -match '^(tests|docs|tools|dist|\.git|\.github|\.modkit)/' -or
        $name -match '^vendor/[^/]+/(tests|docs|\.github|\.modkit)/' -or
        $name -match '(^|/)(baseroms|saves|roms)/' -or
        $name -match '^(assets|data)/generated/' -or
        $name -match '(^|/)\.env($|\.)' -or
        $name -match '\.(gb|gbc|gba|rom|sav|srm|ips|bps|ups|exe|dll|log|bak|zip|7z|pem|key)$' -or
        $name -match '(^|/)programs\.bin$') {
      throw "Non-distributable/development path in updater ZIP: $name"
    }
  }
  function Read-ReleaseText([string]$Name) {
    if (-not $entries.ContainsKey($Name)) { throw "Missing release file: $Name" }
    $reader = New-Object IO.StreamReader($entries[$Name].Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  }
  $manifest = (Read-ReleaseText 'manifest.json') | ConvertFrom-Json
  if ($manifest.id -cne 'voxel_run_bridge' -or
      $manifest.github -cne 'ScottExplores/gen1recomp-voxel-run-bridge' -or
      $manifest.name -cne "Scott's Tweaks" -or $manifest.version -cne $Version -or
      $manifest.entry -cne 'main.lua' -or $manifest.experimental -ne $false -or
      @($manifest.games).Count -ne 2 -or
      @($manifest.games) -notcontains 'gen1' -or @($manifest.games) -notcontains 'gen2') {
    throw 'Manifest version, updater identity, entry or supported games changed unexpectedly'
  }
  $main = Read-ReleaseText 'main.lua'
  if ($main -notmatch ('local RELEASE_VERSION = "' + [regex]::Escape($Version) + '"') -or
      $main -notmatch 'classic_rules = false' -or $main -notmatch 'early_flight = false') {
    throw 'Release source version or default-OFF opt-in rules mismatch'
  }
  $required = @('LICENSE', 'THIRD_PARTY_NOTICES.md', 'README.md', 'CHANGELOG.md',
    'modules/classic_rules.lua', 'lib/ScottJumpButton.lua',
    'vendor/free_fly/lib/EarlyFlight.lua', 'vendor/gen2_voxel/LICENSE-UPSTREAM.txt',
    'vendor/wilds/LICENSE', 'vendor/wilds/THIRD_PARTY_NOTICES.md',
    'vendor/modern_bag_ui/LICENSE')
  foreach ($name in $required) {
    if (-not $entries.ContainsKey($name) -or $entries[$name].Length -eq 0) {
      throw "Required source/notice absent or empty: $name"
    }
  }
  # Integrity's runtime sentinels must be present with exact Android-safe case.
  $integrity = Read-ReleaseText 'modules/integrity.lua'
  $sentinels = [regex]::Matches($integrity, 'path = "([^"]+)"')
  if ($sentinels.Count -lt 25) { throw 'Unexpectedly empty runtime sentinel list' }
  foreach ($match in $sentinels) {
    $name = $match.Groups[1].Value
    if (-not $caseNames.Contains($name) -or $entries[$name].Length -eq 0) {
      throw "Runtime sentinel absent, empty or wrong case: $name"
    }
  }
  [pscustomobject]@{
    Result = 'PASS'; Version = $Version; Files = @($archive.Entries |
      Where-Object { -not $_.FullName.EndsWith('/') }).Count
    Sentinels = $sentinels.Count
    Bytes = (Get-Item -LiteralPath $releasePath).Length
    SHA256 = (Get-FileHash -LiteralPath $releasePath -Algorithm SHA256).Hash.ToLowerInvariant()
  }
} finally { $archive.Dispose() }
