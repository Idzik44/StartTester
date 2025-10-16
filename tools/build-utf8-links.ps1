# Generates docs/UTF8_LINKS.md with RAW links for all files in docs/utf8/.
# Works without git.exe; parses .git/config and .git/HEAD. Safe to run from anywhere under the repo.

function Find-RepoRoot {
    param([string]$startDir)
    $d = (Resolve-Path $startDir).Path
    while ($true) {
        if (Test-Path (Join-Path $d ".git")) { return $d }
        $parent = Split-Path $d
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    return $null
}

# 1) repo root
$hint = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$repo = Find-RepoRoot $hint
if (-not $repo) {
    Write-Error "[build-utf8-links] .git not found. Run from inside the repo."
    exit 1
}

# 2) paths
$utf8Root = Join-Path $repo "docs\utf8"
$docsDir  = Join-Path $repo "docs"
if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Force -Path $docsDir | Out-Null }
$outFile  = Join-Path $docsDir "UTF8_LINKS.md"

if (-not (Test-Path $utf8Root)) {
    Write-Error "[build-utf8-links] Missing folder: $utf8Root (run mirror-to-utf8.ps1 first)."
    exit 1
}

# 3) owner/repo/branch (fallback: Idzik44/StartTester + main)
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

if (-not $ownerRepo) { $ownerRepo = "Idzik44/StartTester" }

try {
    $head = Join-Path $repo ".git\HEAD"
    if (Test-Path $head) {
        $h = Get-Content $head -Raw
        if ($h -match 'ref:\s*refs/heads/(.+)') { $branch = $Matches[1].Trim() }
    }
} catch {}

$rawBase = "https://raw.githubusercontent.com/$ownerRepo/$branch/"

# 4) gather files
$files = Get-ChildItem -Path $utf8Root -Recurse -Include *.mq5,*.mqh -File | Sort-Object FullName
if ($files.Count -eq 0) {
    Write-Error "[build-utf8-links] No *.mq5/*.mqh in docs/utf8 (did mirror run?)."
    exit 1
}

# 5) build records
$items = foreach ($f in $files) {
    $relRepo = $f.FullName.Substring($repo.Length).TrimStart('\') -replace '\\','/'
    [pscustomobject]@{
        Rel  = $relRepo
        Kind = if ($relRepo -match '/Experts/') { 'Experts' } elseif ($relRepo -match '/Include/') { 'Include' } else { 'Other' }
        Raw  = $rawBase + $relRepo
    }
}

$experts = $items | Where-Object { $_.Kind -eq 'Experts' }
$include = $items | Where-Object { $_.Kind -eq 'Include' }
$other   = $items | Where-Object { $_.Kind -eq 'Other' }

# 6) markdown
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("# RAW links for UTF-8 mirror")
$null = $sb.AppendLine()
$null = $sb.AppendLine("> Links point to docs/utf8/** (read-only mirror). Edit originals in MetaEditor.")
$null = $sb.AppendLine("> Repo: $ownerRepo, branch: $branch")
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

# 7) write file
$md = $sb.ToString()
Set-Content -Path $outFile -Value $md -Encoding UTF8
Write-Host "[build-utf8-links] Written: $outFile"
exit 0
