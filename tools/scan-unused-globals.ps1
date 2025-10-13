$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$mql   = Join-Path $root "MQL5"
$out   = Join-Path $root "reports\unused_globals.csv"
$files = Get-ChildItem -Path $mql -Recurse -Include *.mq5,*.mqh

# Wyłap dość szeroko: input/extern/static + typy bazowe
$globDefs = @()
foreach ($f in $files) {
  $i = 0
  foreach ($line in Get-Content $f.FullName) {
    $i++
    if ($line -match '^\s*(?:input|extern|static)?\s*(?:void|int|double|bool|string|datetime|float|uchar|ushort|uint|ulong|color|long|short)\s+([A-Za-z_]\w*)\s*(?:=|;|,).*') {
      $globDefs += [pscustomobject]@{ Name=$Matches[1]; File=$f.FullName; Line=$i }
    }
  }
}
$globDefs = $globDefs | Sort-Object Name -Unique

# Zlicz referencje (bardzo prosto)
$rep = @()
foreach ($g in $globDefs) {
  $count = 0
  foreach ($f in $files) {
    $text = Get-Content $f.FullName -Raw
    $hits = ([regex]::Matches($text, "(?m)\b$([regex]::Escape($g.Name))\b")).Count
    $count += $hits
  }
  $rep += [pscustomobject]@{ Var=$g.Name; Refs=$count; DefFile=$g.File; DefLine=$g.Line }
}

$unused = $rep | Where-Object { $_.Refs -lt 2 } | Sort-Object Var
if (-not (Test-Path (Split-Path $out))) { New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null }
$unused | Export-Csv $out -NoTypeInformation -Encoding UTF8
Write-Host "Zapisano: $out (kandydaci do weryfikacji)"
