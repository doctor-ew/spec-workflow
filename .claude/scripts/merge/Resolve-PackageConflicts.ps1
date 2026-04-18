# Resolve-PackageConflicts.ps1
# Resolves package file conflicts from an in-progress git merge.
# HEAD = OURS (RC), MERGE_HEAD = THEIRS (Dev) by default.
# Parameterised version — no hardcoded paths or SHAs.
#
# Usage:
#   pwsh Resolve-PackageConflicts.ps1 -DryRun
#   pwsh Resolve-PackageConflicts.ps1 -BatchStart 1
#   pwsh Resolve-PackageConflicts.ps1 -BatchStart 16 -OursWins

param(
    [string]$RepoPath    = (Get-Location).Path,
    [string]$PhaseFile   = (Join-Path (Get-Location).Path 'merge-planning/Phase-1-Packages.md'),
    [string]$PlanningDir = (Join-Path (Get-Location).Path 'merge-planning'),
    [string]$MergeBase   = '',
    [int]$BatchStart     = 1,
    [int]$BatchSize      = 15,
    [switch]$DryRun,
    [switch]$OursWins
)

. "$PSScriptRoot\Merge-Lib.ps1"

# Auto-detect merge base if not supplied
if (-not $MergeBase) {
    Push-Location $RepoPath
    $mbLines = (git merge-base HEAD MERGE_HEAD) -split "`n" | Where-Object { $_.Trim() }
    Pop-Location
    if ($mbLines.Count -ne 1) {
        Write-Error "Could not auto-detect merge base (criss-cross merge or not in a merge). Supply -MergeBase explicitly."
        exit 1
    }
    $MergeBase = $mbLines[0].Trim()
}

$DECISIONS_DIR = [IO.Path]::GetFullPath("$PlanningDir\Decisions\Phase-1")

if (-not $DryRun -and -not (Test-Path $DECISIONS_DIR)) {
    New-Item -ItemType Directory -Path $DECISIONS_DIR | Out-Null
}

# --- Read pending files ---
$phaseContent = [IO.File]::ReadAllText([IO.Path]::GetFullPath($PhaseFile))
$pending = [regex]::Matches($phaseContent, '\| `\[ \]` \| ([^|]+) \|') |
    ForEach-Object { $_.Groups[1].Value.Trim() }

if ($pending.Count -eq 0) {
    Write-Host "No pending files in phase file."
    exit 0
}

$batch = $pending | Select-Object -Skip ($BatchStart - 1) -First $BatchSize
Write-Host "Processing files $BatchStart to $($BatchStart + $batch.Count - 1) of $($pending.Count) pending."
if ($DryRun) { Write-Host "[DRY RUN - no files will be modified]" }
Write-Host ""

$processed = 0

foreach ($relPath in $batch) {
    $fullPath = Join-Path $RepoPath $relPath
    Write-Host "--- $relPath"

    if (-not (Test-Path $fullPath)) {
        Write-Warning "  File not found: $fullPath -- stopping batch."
        break
    }

    $content  = [IO.File]::ReadAllText($fullPath)
    $fileType = Get-FileType $relPath
    $blocks   = @(Get-ConflictBlocks $content)

    if ($blocks.Count -eq 0) {
        Write-Host "  No conflict markers -- marking complete."
        if (-not $DryRun) { Update-PhaseFileStatus $PhaseFile $relPath '[x]' | Out-Null }
        $processed++
        continue
    }

    Write-Host "  $($blocks.Count) conflict block(s) found. File type: $fileType"

    $fileDecisions = [System.Collections.Generic.List[hashtable]]::new()
    $fileFlags     = [System.Collections.Generic.List[string]]::new()
    $shouldFlag    = $false
    $resolvedContent = $content

    foreach ($block in $blocks) {
        if ($shouldFlag) { break }

        if ((Test-HasNonPackageContent $block.Ours $fileType) -or
            (Test-HasNonPackageContent $block.Theirs $fileType)) {
            $shouldFlag = $true
            $fileFlags.Add("Non-package content detected in conflict block")
            break
        }

        if ($fileType -eq 'csproj') {
            $csprojResult = Resolve-CsprojBlock $block.Ours $block.Theirs -OursWins:$OursWins
            foreach ($d in $csprojResult.Decisions) { $fileDecisions.Add($d) }
            if ($csprojResult.ShouldFlag) {
                $shouldFlag = $true
                foreach ($r in $csprojResult.FlagReasons) { $fileFlags.Add($r) }
                break
            }
            $resolvedContent = $resolvedContent.Replace($block.FullMatch, $csprojResult.Resolved)
            continue
        }

        $ourEntries   = Get-PackageEntries $block.Ours $fileType
        $theirEntries = Get-PackageEntries $block.Theirs $fileType

        if ($ourEntries.Count -eq 0 -and $theirEntries.Count -eq 0) {
            $shouldFlag = $true
            $fileFlags.Add("Conflict block contains no recognizable package entries")
            break
        }

        $resolvedLines = [System.Collections.Generic.List[string]]::new()
        $allIds = (@($ourEntries.Keys) + @($theirEntries.Keys)) | Sort-Object -Unique

        foreach ($id in $allIds) {
            $hasOurs   = $ourEntries.ContainsKey($id)
            $hasTheirs = $theirEntries.ContainsKey($id)

            if ($hasOurs -and $hasTheirs) {
                $ourVer   = $ourEntries[$id].Version
                $theirVer = $theirEntries[$id].Version
                $cmp      = Compare-NuGetVersions $ourVer $theirVer

                if ($null -eq $cmp) {
                    $shouldFlag = $true
                    $fileFlags.Add("  ${id}: unparseable versions '$ourVer' vs '$theirVer'")
                    break
                }

                if ($cmp -eq 0) {
                    $resolvedLines.Add($ourEntries[$id].Block)
                    $fileDecisions.Add(@{ Package = $id; Ours = $ourVer; Theirs = $theirVer; Resolution = "Same version -- kept" })
                } elseif (($cmp -gt 0 -and -not $OursWins) -or ($cmp -lt 0 -and $OursWins)) {
                    $resolvedLines.Add($ourEntries[$id].Block)
                    $winner = if ($OursWins) { 'RC (higher)' } else { 'HEAD (higher) [UNUSUAL: verify]' }
                    $fileDecisions.Add(@{ Package = $id; Ours = $ourVer; Theirs = $theirVer; Resolution = "Took $winner" })
                    if ($cmp -gt 0) {
                        $fileFlags.Add("  ${id}: HEAD ($ourVer) > MERGE_HEAD ($theirVer) -- preferred side (MERGE_HEAD) is lower, verify this is intentional")
                    } else {
                        $fileFlags.Add("  ${id}: MERGE_HEAD ($theirVer) > HEAD ($ourVer) -- preferred side (HEAD) is lower, verify this is intentional")
                    }
                } else {
                    $preferred = if ($OursWins) { $ourEntries[$id].Block } else { $theirEntries[$id].Block }
                    $resolvedLines.Add($preferred)
                    $winner = if ($OursWins) { 'RC (higher)' } else { 'Dev (higher)' }
                    $fileDecisions.Add(@{ Package = $id; Ours = $ourVer; Theirs = $theirVer; Resolution = "Took $winner" })
                }
            } elseif ($hasOurs) {
                $resolvedLines.Add($ourEntries[$id].Block)
                $fileDecisions.Add(@{ Package = $id; Ours = $ourEntries[$id].Version; Theirs = "--"; Resolution = "HEAD only -- kept" })
            } else {
                $resolvedLines.Add($theirEntries[$id].Block)
                $fileDecisions.Add(@{ Package = $id; Ours = "--"; Theirs = $theirEntries[$id].Version; Resolution = "MERGE_HEAD only -- kept" })
            }
        }

        if ($shouldFlag) { break }

        $closingTags = @{ 'packages.config' = '</packages>'; 'nuspec' = '</dependencies>' }
        if ($closingTags.ContainsKey($fileType)) {
            $tag = $closingTags[$fileType]
            $tagMatch = [regex]::Match($block.Ours + "`n" + $block.Theirs, '[ \t]*' + [regex]::Escape($tag))
            if ($tagMatch.Success) { $resolvedLines.Add($tagMatch.Value) }
        }

        $resolvedBlock = $resolvedLines -join "`r`n"
        $resolvedContent = $resolvedContent.Replace($block.FullMatch, $resolvedBlock)
    }

    if ($shouldFlag) {
        Write-Host "  [!] FLAGGED:"
        foreach ($f in $fileFlags) { Write-Host "      $f" }
        if (-not $DryRun) {
            Update-PhaseFileStatus $PhaseFile $relPath '[!]' | Out-Null
            & "$PSScriptRoot\Get-MergeBaseDiffs.ps1" -RepoPath $RepoPath -FilePath $relPath -PlanningDir $PlanningDir -MergeBase $MergeBase
        }
    } else {
        Write-Host "  Decisions:"
        foreach ($d in $fileDecisions) {
            Write-Host "    $($d.Package): $($d.Ours) vs $($d.Theirs) -- $($d.Resolution)"
        }

        $resolvedContent = [regex]::Replace($resolvedContent, '(?s)<<<<<<< [^\r\n]+\r?\n[ \t\r\n]*=======\r?\n[ \t\r\n]*>>>>>>> [^\r\n]+(\r?\n)?', '')

        if ($resolvedContent -match '<<<<<<< |>>>>>>> ') {
            $shouldFlag = $true
            $fileFlags.Add("Conflict markers remain after resolution -- Replace() failed on one or more blocks")
        }

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would write resolved file."
        } elseif ($shouldFlag) {
            Write-Host "  [!] FLAGGED:"
            foreach ($f in $fileFlags) { Write-Host "      $f" }
            Update-PhaseFileStatus $PhaseFile $relPath '[!]' | Out-Null
            & "$PSScriptRoot\Get-MergeBaseDiffs.ps1" -RepoPath $RepoPath -FilePath $relPath -PlanningDir $PlanningDir -MergeBase $MergeBase
        } else {
            try {
                [IO.File]::WriteAllText($fullPath, $resolvedContent, [Text.Encoding]::UTF8)
                & git -C $RepoPath add $relPath
                Update-PhaseFileStatus $PhaseFile $relPath '[x]' | Out-Null

                $decId = Get-NextDecisionId $DECISIONS_DIR
                $detailPath = Join-Path $DECISIONS_DIR "$decId.md"

                $sb = [System.Text.StringBuilder]::new()
                $sb.AppendLine("# $decId -- $relPath") | Out-Null
                $sb.AppendLine("") | Out-Null
                $sb.AppendLine("**Result:** Auto-resolved") | Out-Null
                $sb.AppendLine("**Processed:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
                $sb.AppendLine("**Resolved by:** Script (Resolve-PackageConflicts.ps1)") | Out-Null
                $sb.AppendLine("") | Out-Null
                $sb.AppendLine("| Package | Ours (HEAD) | Theirs (MERGE_HEAD) | Resolution |") | Out-Null
                $sb.AppendLine("|---------|-------------|----------------------|------------|") | Out-Null
                foreach ($d in $fileDecisions) {
                    $sb.AppendLine("| $($d.Package) | $($d.Ours) | $($d.Theirs) | $($d.Resolution) |") | Out-Null
                }
                [IO.File]::WriteAllText($detailPath, $sb.ToString(), [Text.Encoding]::UTF8)

                Write-Host "  [x] Resolved. Decision: $decId"
            } catch {
                Write-Host ""
                Write-Error "  UNEXPECTED ERROR on '$relPath': $_"
                Write-Host ""
                Write-Host "  To restore this file to its conflicted state, run:"
                Write-Host "    git -C `"$RepoPath`" checkout -m -- `"$relPath`""
                Write-Host ""
                Write-Host "  Batch stopped. Resume from BatchStart $($BatchStart + $processed)"
                exit 1
            }
        }
    }

    $processed++
    Write-Host ""
}

Write-Host "Batch complete. Processed $processed file(s)."

if (-not $DryRun) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "WARNING: Do not manually edit any file already marked [x] in the phase file."
    Write-Host "If a resolved file needs correction, restore it first:"
    Write-Host "  git -C `"$RepoPath`" checkout -m -- <relative-path>"
    Write-Host "Then re-run the script from that file using -BatchStart."
    Write-Host "=========================================="
}
