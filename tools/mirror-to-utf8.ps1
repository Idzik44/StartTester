# Tworzy/aktualizuje kopie .mq5/.mqh w UTF-8 (bez BOM) w docs/utf8/, zachowując strukturę.
# Uruchamiaj z katalogu repo lub z hooków gita.

param(
  [string]$Src = "$PSScriptRoot\..\MQL5",
  [string]$Dst = "$PSScriptRoot\..\docs\utf8"
)

$Src = (Resolve-Path $Src).Path
$Dst = (Resolve-Path $Dst -ErrorAction SilentlyContinue)
if (-not $Dst) { New-Item -ItemType Directory -Force -Path "$PSScriptRoot\..\docs\utf8" | Out-Null; $Dst = (Resolve-Path "$PSScriptRoot\..\docs\utf8").Path }

$files = Get-ChildItem -Path $Src -Recurse -Include *.mq5,*.mqh
$updated = 0

foreach ($f in $files) {
  $rel = $f.FullName.Substring($Src.Length).TrimStart('\')
  $outPath = Join-Path $Dst $rel
  $outDir  = Split-Path $outPath
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

  $srcText = Get-Content $f.FullName -Raw
  $dstText = if (Test-Path $outPath) { Get-Content $outPath -Raw -ErrorAction SilentlyContinue } else { $null }

  if ($null -eq $dstText -or $dstText -ne $srcText) {
    # zapis w UTF-8 bez BOM
    [System.IO.File]::WriteAllText($outPath, $srcText, (New-Object System.Text.UTF8Encoding($false)))
    $updated++
  }
}

Write-Host "mirror-to-utf8: updated $updated file(s)."
exit 0
