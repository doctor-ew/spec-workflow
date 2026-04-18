# Get-ConflictList.ps1
# Reads git status --porcelain from a repo with a merge in progress
# and writes a structured conflict list to the planning directory.
# Parameterised version — no hardcoded paths.
#
# Usage:
#   pwsh Get-ConflictList.ps1 -RepoPath /path/to/repo -OutputPath /path/to/ConflictList.md
#   pwsh Get-ConflictList.ps1                          # defaults to current directory

param(
    [string]$RepoPath   = (Get-Location).Path,
    [string]$OutputPath = (Join-Path (Get-Location).Path 'merge-planning/ConflictList.md')
)

$CATEGORY_ORDER = @('UU','AA','DD','AU','UA','DU','UD')
$CATEGORY_LABELS = @{
    UU = 'Both modified'
    AA = 'Both added'
    DD = 'Both deleted'
    AU = 'Added by us'
    UA = 'Added by them'
    DU = 'Deleted by us'
    UD = 'Deleted by them'
}

# --- Collect raw status ---
Push-Location $RepoPath
$lines = git status --porcelain
Pop-Location

if (-not $lines) {
    Write-Error "No output from git status. Verify repo path and that a merge is in progress."
    exit 1
}

# --- Parse into conflict categories ---
$categories = @{}
foreach ($code in $CATEGORY_ORDER) {
    $categories[$code] = [System.Collections.Generic.List[string]]::new()
}
$unrecognized = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    if ($line.Length -lt 4) { continue }
    $code = $line.Substring(0, 2).Trim()
    $file = $line.Substring(3).Trim()
    if ($categories.ContainsKey($code)) {
        $categories[$code].Add($file)
    } else {
        $unrecognized.Add("[$code] $file")
    }
}

# --- Build output ---
$sb = [System.Text.StringBuilder]::new()
$generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$total = ($categories.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

$sb.AppendLine("# Conflict List") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("**Generated:** $generated") | Out-Null
$sb.AppendLine("**Repo:** $RepoPath") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("## Summary") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("| Code | Meaning | Count |") | Out-Null
$sb.AppendLine("|------|---------|-------|") | Out-Null
foreach ($code in $CATEGORY_ORDER) {
    $sb.AppendLine("| $code | $($CATEGORY_LABELS[$code]) | $($categories[$code].Count) |") | Out-Null
}
$sb.AppendLine("| **Total** | | **$total** |") | Out-Null
$sb.AppendLine("") | Out-Null

foreach ($code in $CATEGORY_ORDER) {
    $files = $categories[$code] | Sort-Object
    if ($files.Count -eq 0) { continue }
    $sb.AppendLine("## $code - $($files.Count) file(s)") | Out-Null
    $sb.AppendLine("") | Out-Null
    foreach ($f in $files) { $sb.AppendLine("- $f") | Out-Null }
    $sb.AppendLine("") | Out-Null
}

if ($unrecognized.Count -gt 0) {
    $sb.AppendLine("## Unrecognized codes") | Out-Null
    $sb.AppendLine("") | Out-Null
    foreach ($f in $unrecognized) { $sb.AppendLine("- $f") | Out-Null }
    $sb.AppendLine("") | Out-Null
}

# --- Write output ---
$outputDir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $sb.ToString(), [Text.Encoding]::UTF8)
Write-Host "Done. $total conflict(s) written to: $OutputPath"
