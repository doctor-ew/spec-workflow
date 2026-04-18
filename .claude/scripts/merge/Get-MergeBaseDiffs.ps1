# Get-MergeBaseDiffs.ps1
# For flagged files, outputs compact per-file diffs showing what each branch changed
# relative to the merge base, plus commit messages explaining why.
# Read-only — never modifies any file.
# Parameterised version — no hardcoded paths or SHAs.
#
# Usage:
#   pwsh Get-MergeBaseDiffs.ps1 -FilePath "Some/File.csproj" -RepoPath /path/to/repo
#   pwsh Get-MergeBaseDiffs.ps1 -FilePath "Some/File.csproj"  # defaults to current dir

param(
    [string]$RepoPath    = (Get-Location).Path,
    [string]$FilePath    = "",
    [string]$PlanningDir = (Join-Path (Get-Location).Path 'merge-planning'),
    [string]$MergeBase   = '',
    [string]$OutputFile  = ""
)

if (-not $FilePath) {
    Write-Error "No -FilePath specified."
    exit 1
}

# Auto-detect merge base if not supplied
if (-not $MergeBase) {
    Push-Location $RepoPath
    $mbLines = (git merge-base HEAD MERGE_HEAD) -split "`n" | Where-Object { $_.Trim() }
    Pop-Location
    if ($mbLines.Count -ne 1) {
        Write-Error "Could not auto-detect merge base. Supply -MergeBase explicitly."
        exit 1
    }
    $MergeBase = $mbLines[0].Trim()
}

$flaggedDir = [IO.Path]::GetFullPath("$PlanningDir\FlaggedDiffs")
if (-not (Test-Path $flaggedDir)) { New-Item -ItemType Directory -Path $flaggedDir | Out-Null }

if (-not $OutputFile) {
    $safeName = $FilePath -replace '[/\\]', '_'
    $OutputFile = Join-Path $flaggedDir "$safeName.md"
}

function Get-Diff {
    param([string]$From, [string]$To, [string]$File)
    Push-Location $RepoPath
    $result = git diff $From $To -- $File 2>&1
    Pop-Location
    return $result -join "`n"
}

function Get-Log {
    param([string]$From, [string]$To, [string]$File)
    Push-Location $RepoPath
    $result = git log --oneline "$From..$To" -- $File 2>&1
    Pop-Location
    return $result -join "`n"
}

$rcDiff  = Get-Diff $MergeBase "HEAD"       $FilePath
$devDiff = Get-Diff $MergeBase "MERGE_HEAD" $FilePath
$rcLog   = Get-Log  $MergeBase "HEAD"       $FilePath
$devLog  = Get-Log  $MergeBase "MERGE_HEAD" $FilePath

$sb = [System.Text.StringBuilder]::new()
$sb.AppendLine("## $FilePath") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
$sb.AppendLine("") | Out-Null

$sb.AppendLine("### RC commits (HEAD since merge base)") | Out-Null
$sb.AppendLine("``````") | Out-Null
$sb.AppendLine($(if ($rcLog) { $rcLog } else { "(none)" })) | Out-Null
$sb.AppendLine("``````") | Out-Null
$sb.AppendLine("") | Out-Null

$sb.AppendLine("### Dev commits (MERGE_HEAD since merge base)") | Out-Null
$sb.AppendLine("``````") | Out-Null
$sb.AppendLine($(if ($devLog) { $devLog } else { "(none)" })) | Out-Null
$sb.AppendLine("``````") | Out-Null
$sb.AppendLine("") | Out-Null

$sb.AppendLine("### RC changes (diff merge-base -> HEAD)") | Out-Null
$sb.AppendLine("``````diff") | Out-Null
$sb.AppendLine($(if ($rcDiff) { $rcDiff } else { "(no changes)" })) | Out-Null
$sb.AppendLine("``````") | Out-Null
$sb.AppendLine("") | Out-Null

$sb.AppendLine("### Dev changes (diff merge-base -> MERGE_HEAD)") | Out-Null
$sb.AppendLine("``````diff") | Out-Null
$sb.AppendLine($(if ($devDiff) { $devDiff } else { "(no changes)" })) | Out-Null
$sb.AppendLine("``````") | Out-Null
$sb.AppendLine("") | Out-Null
$sb.AppendLine("---") | Out-Null
$sb.AppendLine("") | Out-Null

[IO.File]::AppendAllText($OutputFile, $sb.ToString(), [Text.Encoding]::UTF8)
Write-Host "  Diff written to $OutputFile"
