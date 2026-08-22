# Runs the fused-renderer load check. The Lua side cannot list directories
# without lfs, so the vendored code tree is enumerated here and handed over as
# a file list.
[CmdletBinding()]
param(
  [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$EngineRoot = (Join-Path $env:TEMP 'codex_gen1recomp_source_v0.1.96')
)
$ErrorActionPreference = 'Stop'
$lua = (Get-Command luajit -ErrorAction Stop).Source
$root = [IO.Path]::GetFullPath($ModRoot)
$list = Join-Path ([IO.Path]::GetTempPath()) 'fused_files.txt'

$files = Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object {
    ($_.Extension -eq '.lua' -or $_.Name -eq 'manifest.json' -or
      $_.Name -eq 'mod.card' -or $_.Name -eq 'LICENSE')
  } |
  ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
  Where-Object {
    $_ -notlike '.git/*' -and $_ -notlike 'tests/*' -and $_ -notlike 'docs/*'
  } | Sort-Object

# UTF8 without a BOM: LuaJIT's io.lines would otherwise hand the first path
# back with a byte-order mark glued to the front.
[IO.File]::WriteAllLines($list, $files, (New-Object Text.UTF8Encoding($false)))
Write-Host "staged $($files.Count) files"

Push-Location $root
$exitCode = 0
try {
  & $lua 'tests/fused_renderer_load.lua' $root $EngineRoot $list
  $exitCode = $LASTEXITCODE
}
finally { Pop-Location }
exit $exitCode
