# Compile StartTester10.mq5 and collect warnings into reports\compile_warnings.txt

$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# 1) Try to locate MetaEditor64.exe
$metaCandidates = @(
  "C:\Program Files\MetaTrader 5\metaeditor64.exe",
  "C:\Program Files\MetaTrader 5 IC Markets (SC)\MetaEditor64.exe",
  "C:\Program Files\MetaTrader 5 IC Markets\MetaEditor64.exe"
)
$meta = $null
foreach ($c in $metaCandidates) {
  if (Test-Path $c) { $meta = $c; break }
}
if (-not $meta) {
  $found = Get-ChildItem "C:\Program Files" -Recurse -Filter metaeditor64.exe -ErrorAction SilentlyContinue | Select-Object -Expand FullName -First 1
  if ($found) { $meta = $found }
}

if (-not $meta) {
  Write-Error "MetaEditor64.exe not found. Edit this script and set `$meta manually."
  exit 1
}

# 2) Paths
$main = "C:\EA\StartTester\MQL5\Experts\StartTester\StartTester11.mq5"
if (-not (Test-Path $main)) { Write-Error "Main not found: $main"; exit 1 }
$log  = Join-Path $root "reports\compile_warnings.txt"
$repDir = Split-Path $log
if (-not (Test-Path $repDir)) { New-Item -ItemType Directory -Force -Path $repDir | Out-Null }

if (-not (Test-Path $main)) {
  Write-Error "Main file not found: $main"
  exit 1
}

# 3) Run compile with log
& $meta "/compile:$main" "/log:$log"

Write-Host ""
Write-Host "MetaEditor: $meta"
Write-Host "Log file : $log"

# 4) Print warning highlights (if any)
if (Test-Path $log) {
  $hits = Select-String -Path $log -Pattern "warning","not used","deprecated" -SimpleMatch
  if ($hits -and $hits.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings (first 50 matches):"
    $hits | Select-Object -First 50 | ForEach-Object { $_.Line }
  } else {
    Write-Host ""
    Write-Host "No matching warnings found."
  }
} else {
  Write-Host "Log file not found after compile."
}
