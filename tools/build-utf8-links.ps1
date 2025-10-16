<# 
Generuje docs/UTF8_LINKS.md z RAW linkami do wszystkich plików w docs/utf8/.
Działa niezależnie od miejsca uruchomienia (sam szuka .git).
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
if (-not $repo) { Write-Error "Nie znalazłem .git – uruchom w lub spod folderu repo."; exit 1 }

# 2) Ścieżki
$utf8Root = Join-Path $repo "docs\utf8"
$outFile  = Join-Path $repo "docs\UTF8_LINKS.md"
if (-not (Test-Path $utf8Root)) { Write-Error "Brak folderu: $utf8Root (najpierw zrób mirror UTF-8)."; exit 1 }

# 3) Dane o zdalnym i gałęzi
#    (obsługa zarówno HTTPS jak i SSH)
$git = "git"
try { $null = & $git -C $repo --version 2>$null } catch { $git = $null }
if ($git) {
  $origin = (& git -C $repo config --get remote.origin.url).Trim()
  $branch = (& git -C $repo rev-parse --abbrev-ref HEAD).Trim()
} else {
  # fallback – ustaw ręcznie jeśli git nie jest w PATH
  $origin = "https://github.com/Idzik44/StartTester.git"
  $branch = "main"
}

# 4) Zbuduj base do RAW
# przykłady:
#  - https://github.com/owner/repo.git           -> https://raw.githubusercontent.com/owner/repo/branch/
#  - git@github.com:owner/repo.git               -> https://raw.githubusercontent.com/owner/repo/branch/
#  - https://github.com/owner/repo               -> https://raw.githubusercontent.com/owner/repo/branch/
$ownerRepo = $null
if ($origin -match 'github\.com[:/]+([^/]+)/([^/.]+)') {
  $ownerRepo = "$($Matches[1])/$($Matches[2])"
} else {
  Write-Warning "Nie udało się sparsować remote.origin.url ($origin). Używam domyślnego owner/repo."
  $ownerRepo = "Idzik44/StartTester"
}
$rawBase = "https://raw.githubusercontent.com/$ownerRepo/$branch/"

# 5) Zbierz pliki
$files = Get-ChildItem -Path $utf8Root -Recurse -Include *.mq5,*.mqh -File | Sort-Object FullName
if ($files.Count -eq 0) { Write-Error "W docs/utf8 nie ma żadnych *.mq5/*.mqh"; exit 1 }

# 6) Grupuj logicznie (Experts / Include / inne)
$items = foreach ($f in $files) {
  $rel = $f.FullName.Substring($repo.Length).TrimStart('\') -replace '\\','/'
  [pscustomobject]@{
    Rel=$rel
    Kind = if ($rel -match '/MQL5/Experts/') { 'Experts' } elseif ($rel -match '/MQL5/Include/') { 'Include' } else { 'Other' }
    Raw = $rawBase + $rel
  }
}

$experts = $items | Where-Object {$_.Kind -eq 'Experts'}
$include = $items | Where-Object {$_.Kind -eq 'Include'}
$other   = $items | Where-Object {$_.Kind -eq 'Other'}

# 7) Zbuduj markdown
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("# RAW linki do kopii UTF-8")
$null = $sb.AppendLine()
$null = $sb.AppendLine("> Te linki wskazują na docs/utf8/** i służą tylko do przeglądu. Edycję robimy w MetaEditorze w oryginalnych plikach.")
$null = $sb.AppendLine()

if ($experts.Count -gt 0) {
  $null = $sb.AppendLine("## Experts")
  foreach ($e in $experts) { $null = $sb.AppendLine("- [$($e.Rel)]($($e.Raw))") }
  $null = $sb.AppendLine()
}
if ($include.Count -gt 0) {
  $null = $sb.AppendLine("## Include")
  foreach ($i in $include) { $null = $sb.AppendLine("- [$($i.Rel)]($($i.Raw))") }
  $null = $sb.AppendLine()
}
if ($other.Count -gt 0) {
  $null = $sb.AppendLine("## Other")
  foreach ($o in $other) { $null = $sb.AppendLine("- [$($o.Rel)]($($o.Raw))") }
  $null = $sb.AppendLine()
}

# 8) Zapis
$sb.ToString() | Set-Content $outFile -Encoding UTF8
Write-Host "Zapisano: $outFile"
