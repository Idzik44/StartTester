<#
Tworzy/aktualizuje kopie .mq5/.mqh w UTF-8 (bez BOM) w docs/utf8/, zachowując strukturę.
Działa niezależnie od miejsca wywołania (sam znajduje root repo).
#>

# --- znajdź root repo ---
function Find-RepoRoot {
  param([string]$startDir)
  $d = Resolve-Path $startDir
  while ($d) {
    if (Test-Path (Join-Path $d ".git")) { return $d }
    $parent = Split-Path $d
    if ($parent -and $parent -ne $d) { $d = $parent } else { break }
  }
  return $null
}

# jeśli odpalono ze skryptu – użyj jego folderu; inaczej użyj bieżącego
$hint = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$repo = Find-RepoRoot $hint
if (-not $repo) {
  Write-Error "Nie znalazłem katalogu repo (.git). Otwórz konsolę w folderze repo (np. C:\EA\StartTester) albo wskaż ręcznie."
  exit 1
}

$src = Join-Path $repo "MQL5"
$dst = Join-Path $repo "docs\utf8"

if (-not (Test-Path $src)) {
  Write-Error "Brak folderu źródeł: $src"
  exit 1
}

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$files = Get-ChildItem -Path $src -Recurse -Include *.mq5,*.mqh -File
$updated = 0

foreach ($f in $files) {
  $rel     = $f.FullName.Substring($src.Length).TrimStart('\')
  $outPath = Join-Path $dst $rel
  $outDir  = Split-Path $outPath
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

  $srcText = Get-Content $f.FullName -Raw
  $dstText = if (Test-Path $outPath) { Get-Content $outPath -Raw -ErrorAction SilentlyContinue } else { $null }

  if ($null -eq $dstText -or $dstText -ne $srcText) {
    # zapis w UTF-8 (bez BOM)
    [System.IO.File]::WriteAllText($outPath, $srcText, (New-Object System.Text.UTF8Encoding($false)))
    $updated++
    Write-Host "→ $rel"
  }
}

Write-Host "mirror-to-utf8: updated $updated file(s)."
exit 0

