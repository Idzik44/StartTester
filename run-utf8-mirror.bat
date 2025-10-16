<# 
Generuje docs/UTF8_LINKS.md z RAW linkami do wszystkich plików w docs/utf8/.
Działa niezależnie od miejsca uruchomienia (sam szuka .git).
Nie wymaga git.exe w PATH (parsuje .git\config); ma fallback owner/repo/branch.
#>

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

# 1) Repo root
$hint = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$repo = Find-RepoRoot $hint
if (-not $repo) { Write-Error "[build-utf8-links] Nie znalazłem .git – uruchom w lub spod folderu repo."; exit 1 }

# 2) Ścieżki
$utf8Root = Join-Path $repo "docs\utf8"
$outFile  = Join-Path $repo "docs\UTF8_LINKS.md"

if (-not (Test-Path $utf8Root)) {
  Write-Error "[build-utf8-links] Brak folderu: $utf8Root (najpierw uruchom mirror UTF-8)."
  exit 1
}

# 3) Ustal owner/repo/branch
#    Spróbuj z .git\config; jak się nie uda – fallback na Idzik44/StartTester + main
$ownerRepo = $null
$branch    = "main"

try {
  $gitConfig = Join-Path $repo ".git\config"
  if (Test-Path $gitConfig) {
    $cfg = Get-Content $gitConfig -Raw
    if ($cfg -match 'url\s*=\s*(.+)') {
      $origin = $Matches[1].Trim()
      if ($origin -match 'github\.com[:/]+([^/]+)/([^/.]+)') {
        $ownerRepo = "$($Matches[1])/$($Matches[2])"
      }
    }
  }
} catch {}

if (-not $ownerRepo) { $ownerRepo = "Idzik44/StartTester" }  # <- fallback wpisany pod Twój projekt
# Spróbuj odczytać aktualną gałąź z HEAD (bez git.exe)
try {
  $head = Join-Path $repo ".git\HEAD"
  if (Test-Path $head) {
    $h = Get-Content $head -Raw
    if ($h -match 'ref:\s*refs/heads/(.+)') { $branch = $Matches[1].Trim() }
  }
} catch {}

$rawBase = "https://raw.githubusercontent.com/$ownerRepo/$branch/"

# 4) Zbierz pliki
$files = Get-ChildItem -Path $utf8Root -Recurse -Include *.mq5,*.mqh -File | Sort-Object FullName
if ($files.Count -eq 0) {
  Write-Error "[build-utf8-links] W docs/utf8 nie ma żadnych *.mq5/*.mqh (czy mirror zadziałał?)."
  exit 1
}

# 5) Przygotuj rekordy
$items = foreach ($f in $files) {
  $relRepo = $f.FullName.Substring($repo.Length).TrimStart('\') -replace '\\','/'
  [pscustomobject]@{
    Rel = $relRepo
    Kind = if ($relRepo -match '/MQL5/Experts/') { 'Experts' } elseif ($relRepo -match '/MQL5/Include/') { 'Include' } else { 'Other' }
    Raw = $rawBase + $relRepo
  }
}

$experts = $items | Where-Object {$_.Kind -eq 'Experts'}
$include = $items | Where-Object {$_.Kind -eq 'Include'}
$other   = $items | Where-Object {$_.Kind -eq 'Other'}

# 6) Zbuduj markdown
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLin
