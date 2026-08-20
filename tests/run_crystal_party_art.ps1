# Runs the real fused-loader Crystal party/Summary art regression under both
# supported Lua 5.1 runtimes.  Only the two Bulbasaur frame folders are staged;
# that keeps the focused test quick while preserving exact-case asset lookup.
[CmdletBinding()]
param(
  [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$EngineRoot = (Join-Path $env:TEMP 'codex_gen1recomp_source_v0.1.96')
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ModRoot)
$list = Join-Path ([IO.Path]::GetTempPath()) (
  'crystal_party_art_files_{0}_{1}.txt' -f $PID, [Guid]::NewGuid().ToString('N'))

$normalRoot = [IO.Path]::GetFullPath(
  (Join-Path $root 'vendor\crystal\assets\front\normal\1'))
$shinyRoot = [IO.Path]::GetFullPath(
  (Join-Path $root 'vendor\crystal\assets\front\shiny\1'))
$files = Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object {
    $full = $_.FullName
    $_.Extension -eq '.lua' -or $_.Name -eq 'manifest.json' -or
      $_.Name -eq 'mod.card' -or
      ($_.Extension -eq '.png' -and
        ($full.StartsWith($normalRoot + [IO.Path]::DirectorySeparatorChar,
          [StringComparison]::OrdinalIgnoreCase) -or
         $full.StartsWith($shinyRoot + [IO.Path]::DirectorySeparatorChar,
          [StringComparison]::OrdinalIgnoreCase)))
  } |
  ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
  Where-Object {
    $_ -notlike '.git/*' -and $_ -notlike 'tests/*' -and
      $_ -notlike 'docs/*' -and $_ -notlike 'dist/*'
  } | Sort-Object -Unique

[IO.File]::WriteAllLines($list, $files, (New-Object Text.UTF8Encoding($false)))
Write-Host "staged $($files.Count) focused files"

$interpreters = @('luajit', 'lua') | ForEach-Object {
  Get-Command $_ -ErrorAction SilentlyContinue
} | Where-Object { $_ -ne $null }
if ($interpreters.Count -eq 0) { throw 'Neither luajit nor lua is installed.' }

$exitCode = 0
Push-Location $root
try {
  foreach ($interpreter in $interpreters) {
    Write-Host "running $($interpreter.Name)"
    & $interpreter.Source 'tests/crystal_party_art.lua' $root $EngineRoot $list
    if ($LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE; break }
  }
}
finally {
  Pop-Location
  Remove-Item -LiteralPath $list -Force -ErrorAction SilentlyContinue
}
exit $exitCode
