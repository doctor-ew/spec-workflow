# Validate-Resolved.ps1
# Scans [x]-marked files for remaining conflict markers and structural issues.
# Parameterised version — no hardcoded paths.
#
# Usage:
#   pwsh Validate-Resolved.ps1 -RepoPath /path/to/repo -PhaseFile /path/to/Phase-1-Packages.md
#   pwsh Validate-Resolved.ps1 -RepoPath /path/to/repo -PlanningDir /path/to/planning -AllPhases

param(
    [string]$RepoPath    = (Get-Location).Path,
    [string]$PhaseFile   = '',
    [string]$PlanningDir = (Join-Path (Get-Location).Path 'merge-planning'),
    [switch]$AllPhases
)

function Get-ResolvedFiles {
    param([string]$PhaseFilePath)
    $content = [IO.File]::ReadAllText($PhaseFilePath)
    [regex]::Matches($content, '\| `\[x\]` \| ([^|]+) \|') |
        ForEach-Object { $_.Groups[1].Value.Trim() }
}

function Test-PhaseFile {
    param([string]$PhaseFilePath, [string]$RepoPath)
    $issues = @()
    $done = Get-ResolvedFiles $PhaseFilePath

    foreach ($rel in $done) {
        $full = Join-Path $RepoPath $rel
        if (-not (Test-Path $full)) { continue }
        $text = [IO.File]::ReadAllText($full)
        $name = [IO.Path]::GetFileName($rel).ToLower()
        $ext  = [IO.Path]::GetExtension($rel).ToLower()

        if ($name -eq 'packages.config' -and $text -notmatch '</packages>') {
            $issues += "MISSING </packages>: $rel"
        }
        if ($ext -eq '.nuspec' -and $text -notmatch '</dependencies>') {
            $issues += "MISSING </dependencies>: $rel"
        }
        if ($text -match '<<<<<<<|>>>>>>>') {
            $issues += "CONFLICT MARKERS REMAIN: $rel"
        }
    }
    return @{ Issues = $issues; CheckedCount = $done.Count }
}

$phaseFiles = @()

if ($AllPhases) {
    $phaseFiles = Get-ChildItem $PlanningDir -Filter 'Phase-*.md' | Sort-Object Name
    if ($phaseFiles.Count -eq 0) {
        Write-Host "No Phase-*.md files found in $PlanningDir"
        exit 0
    }
} elseif ($PhaseFile) {
    $phaseFiles = @([PSCustomObject]@{ FullName = [IO.Path]::GetFullPath($PhaseFile) })
} else {
    $default = Join-Path $PlanningDir 'Phase-1-Packages.md'
    if (-not (Test-Path $default)) {
        Write-Error "No phase file found at $default. Specify -PhaseFile or -AllPhases."
        exit 1
    }
    $phaseFiles = @([PSCustomObject]@{ FullName = $default })
}

$allIssues = @()
$totalChecked = 0

foreach ($pf in $phaseFiles) {
    $pfPath = if ($pf.FullName) { $pf.FullName } else { $pf }
    if (-not (Test-Path $pfPath)) {
        Write-Warning "Phase file not found, skipping: $pfPath"
        continue
    }
    $result = Test-PhaseFile $pfPath $RepoPath
    $totalChecked += $result.CheckedCount
    $allIssues += $result.Issues
}

if ($allIssues.Count -eq 0) {
    Write-Host "All $totalChecked resolved file(s) OK."
} else {
    Write-Host "$($allIssues.Count) issue(s) found:"
    $allIssues | ForEach-Object { Write-Host "  $_" }
    exit 1
}
