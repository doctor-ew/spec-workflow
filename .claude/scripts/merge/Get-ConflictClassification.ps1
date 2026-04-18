# Get-ConflictClassification.ps1
# Classifies UU and AA conflicts from the live merge by file type.
# Parameterised version — no hardcoded paths.
#
# Usage:
#   pwsh Get-ConflictClassification.ps1 -RepoPath /path/to/repo -OutputPath /path/to/ConflictClassification.md

param(
    [string]$RepoPath   = (Get-Location).Path,
    [string]$OutputPath = (Join-Path (Get-Location).Path 'merge-planning/ConflictClassification.md')
)

$EXT_GROUPS = [ordered]@{
    'Packages'   = @('.csproj', '.nuspec')
    'Config'     = @('.config')
    'Pipeline'   = @('.yml', '.yaml')
    'CSharp'     = @('.cs')
    'JavaScript' = @('.js')
    'Views'      = @('.cshtml')
    'Other'      = @()
}

$FILENAME_GROUPS = @{
    'Packages' = @('packages.config')
}

function Get-Group {
    param([string]$File)
    $name = [IO.Path]::GetFileName($File).ToLower()
    $ext  = [IO.Path]::GetExtension($File).ToLower()
    foreach ($entry in $FILENAME_GROUPS.GetEnumerator()) {
        if ($entry.Value -contains $name) { return $entry.Key }
    }
    foreach ($entry in $EXT_GROUPS.GetEnumerator()) {
        if ($entry.Value -contains $ext) { return $entry.Key }
    }
    return 'Other'
}

# --- Collect ---
Push-Location $RepoPath
$lines = git status --porcelain
Pop-Location

if (-not $lines) {
    Write-Error "No output from git status. Verify repo path and that a merge is in progress."
    exit 1
}

$uu = [System.Collections.Generic.List[string]]::new()
$aa = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    if ($line.Length -lt 4) { continue }
    $code = $line.Substring(0, 2).Trim()
    $file = $line.Substring(3).Trim()
    if ($code -eq 'UU') { $uu.Add($file) }
    elseif ($code -eq 'AA') { $aa.Add($file) }
}

# --- Classify UU by group ---
$groups = @{}
foreach ($key in $EXT_GROUPS.Keys) { $groups[$key] = [System.Collections.Generic.List[string]]::new() }
foreach ($file in $uu) { $groups[(Get-Group $file)].Add($file) }

# --- Build output ---
$sb = [System.Text.StringBuilder]::new()
$generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$sb.AppendLine("# Conflict Classification") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("**Generated:** $generated") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("## Summary") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("| Group | Count |") | Out-Null
$sb.AppendLine("|-------|-------|") | Out-Null
foreach ($key in $EXT_GROUPS.Keys) {
    $sb.AppendLine("| UU / $key | $($groups[$key].Count) |") | Out-Null
}
$sb.AppendLine("| AA / Both-added | $($aa.Count) |") | Out-Null
$sb.AppendLine("| **Total** | **$($uu.Count + $aa.Count)** |") | Out-Null
$sb.AppendLine("") | Out-Null

foreach ($key in $EXT_GROUPS.Keys) {
    $files = $groups[$key] | Sort-Object
    if ($files.Count -eq 0) { continue }
    $sb.AppendLine("## UU / $key - $($files.Count) file(s)") | Out-Null
    $sb.AppendLine("") | Out-Null
    foreach ($f in $files) { $sb.AppendLine("- $f") | Out-Null }
    $sb.AppendLine("") | Out-Null
}

if ($aa.Count -gt 0) {
    $sb.AppendLine("## AA / Both-added - $($aa.Count) file(s)") | Out-Null
    $sb.AppendLine("") | Out-Null
    foreach ($f in ($aa | Sort-Object)) { $sb.AppendLine("- $f") | Out-Null }
    $sb.AppendLine("") | Out-Null
}

$outputDir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $sb.ToString(), [Text.Encoding]::UTF8)
Write-Host "Done. $($uu.Count + $aa.Count) conflict(s) classified. Output: $OutputPath"
