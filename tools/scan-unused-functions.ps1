# Uruchamiaj z: C:\EA\StartTester\tools
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$mql   = Join-Path $root "MQL5"
$out   = Join-Path $root "reports\unused_functions.csv"
$files = Get-ChildItem -Path $mql -Recurse -Include *.mq5,*.mqh

# Zbieraj definicje funkcji (typowe typy MQL5)
$funcDefs = @()
foreach ($f in $files) {
  $i = 0
  foreach ($line in Get-Content $f.FullName) {
    $i++
    if ($line -match '^\s*(?:void|int|double|bool|string|datetime|float|uchar|ushort|uint|ulong|color|long|short)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{') {
      $funcDefs += [pscustomobject]@{ Name=$Matches[1]; File=$f.FullName; Line=$i }
    }
  }
}
$funcDefs = $funcDefs | Sort-Object Name -Unique

# Policz użycia nazwy funkcji z "(" w całym projekcie
$report = @()
foreach ($fn in $funcDefs) {
  $count = 0
  foreach ($f in $files) {
    $text = Get-Content $f.FullName -Raw
    $hits = ([regex]::Matches($text, "(?m)\b$([regex]::Escape($fn.Name))\s*\(")).Count
    $count += $hits
  }
  $calls = [Math]::Max(0, $count - 1) # odejmij definicję
  $report += [pscustomobject]@{ Func=$fn.Name; Calls=$calls; DefFile=$fn.File; DefLine=$fn.Line }
}

$unused = $report | Where-Object { $_.Calls -eq 0 } | Sort-Object Func
if (-not (Test-Path (Split-Path $out))) { New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null }
$unused | Export-Csv $out -NoTypeInformation -Encoding UTF8
Write-Host "Zapisano: $out (kandydaci do weryfikacji)"
