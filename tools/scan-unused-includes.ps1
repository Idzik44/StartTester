$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$mql   = Join-Path $root "MQL5"
$out   = Join-Path $root "reports\unused_includes.csv"

$files = Get-ChildItem -Path $mql -Recurse -Include *.mq5,*.mqh
$includes = @()

foreach ($f in $files) {
  $i=0
  foreach ($line in Get-Content $f.FullName) {
    $i++
    if ($line -match '^\s*#include\s+[<"]([^">]+)[">]') {
      $inc = $Matches[1]
      # interesują nas tylko Twoje moduły StartTester/*
      if ($inc -match '^StartTester/') {
        $includes += [pscustomobject]@{ Includer=$f.FullName; Line=$i; Target=$inc }
      }
    }
  }
}

# spłaszczony katalog targetów
$targets = $includes | Select-Object -Expand Target -Unique

# które targety nie są nigdzie includowane (poza miejscem definicji)?
$allText = ($files | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"

$report = foreach ($t in $targets) {
  $pattern = [regex]::Escape($t)
  $hits = ([regex]::Matches($allText, "(?m)#include\s+[<`"]$pattern[>`"]")).Count
  # jeśli include do t pojawia się tylko 1 raz (np. tylko w jednym pliku), a t nie jest wymagany gdzie indziej → kandydat do oceny
  [pscustomobject]@{ Target=$t; IncludeCount=$hits }
}

$unused = $report | Where-Object { $_.IncludeCount -le 1 } | Sort-Object Target
if (-not (Test-Path (Split-Path $out))) { New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null }
$unused | Export-Csv $out -NoTypeInformation -Encoding UTF8
Write-Host "Zapisano: $out"
