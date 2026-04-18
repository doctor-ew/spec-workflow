# Build-PhaseFiles.ps1
# Generates Phase-N-*.md files from ConflictClassification.md.
# Parameterised version — no hardcoded paths.
#
# Usage:
#   pwsh Build-PhaseFiles.ps1 -ClassificationPath /path/to/ConflictClassification.md -OutputDir /path/to/planning

param(
    [string]$ClassificationPath = (Join-Path (Get-Location).Path 'merge-planning/ConflictClassification.md'),
    [string]$OutputDir          = (Join-Path (Get-Location).Path 'merge-planning')
)

$STATUS_LEGEND = @"
## Status Legend
| Symbol | Status |
|--------|--------|
| ``[ ]``  | Not Started |
| ``[>]``  | In Progress |
| ``[!]``  | Flagged for Review |
| ``[x]``  | Complete |

"@

$PHASES = [ordered]@{
    'UU / Packages'   = @{ File = 'Phase-1-Packages.md';  Title = 'Phase 1 - UU / Packages';  Desc = 'Package files (csproj, nuspec, packages.config). Resolve by version preference.' }
    'UU / CSharp'     = @{ File = 'Phase-2-Code.md';      Title = 'Phase 2 - UU / Code';       Desc = 'Code conflicts (cs, js, cshtml). Each file requires individual review.' }
    'UU / JavaScript' = @{ File = 'Phase-2-Code.md';      Title = $null; Desc = $null }
    'UU / Views'      = @{ File = 'Phase-2-Code.md';      Title = $null; Desc = $null }
    'UU / Pipeline'   = @{ File = 'Phase-3-Pipelines.md'; Title = 'Phase 3 - UU / Pipeline';   Desc = 'Pipeline yml files. Each file requires individual review.' }
    'UU / Config'     = @{ File = 'Phase-4-Config.md';    Title = 'Phase 4 - UU / Config';     Desc = 'Config files. Each file requires individual review.' }
    'UU / Other'      = @{ File = 'Phase-5-Other.md';     Title = 'Phase 5 - UU / Other';      Desc = 'Unclassified conflict files. Identify and review before resolving.' }
    'AA / Both-added' = @{ File = 'Phase-6-BothAdded.md'; Title = 'Phase 6 - AA / Both-added'; Desc = 'Files added independently on both branches. Do not resolve without discussion.' }
}

$resolvedInput = [IO.Path]::GetFullPath($ClassificationPath)
if (-not (Test-Path $resolvedInput)) {
    Write-Error "Classification file not found: $resolvedInput. Run Get-ConflictClassification.ps1 first."
    exit 1
}

$lines = [IO.File]::ReadAllLines($resolvedInput)
$sections = [ordered]@{}
$currentKey = $null

foreach ($line in $lines) {
    if ($line -match '^## (.+?) - \d+ file') {
        $currentKey = $Matches[1].Trim()
        $sections[$currentKey] = [System.Collections.Generic.List[string]]::new()
    } elseif ($currentKey -and $line -match '^- (.+)') {
        $sections[$currentKey].Add($Matches[1].Trim())
    }
}

$fileContents = [ordered]@{}

foreach ($sectionKey in $PHASES.Keys) {
    $phase = $PHASES[$sectionKey]
    $outFile = $phase['File']
    $files = if ($sections.Contains($sectionKey)) { $sections[$sectionKey] } else { @() }
    if (-not $fileContents.Contains($outFile)) {
        $fileContents[$outFile] = @{ Title = $phase['Title']; Desc = $phase['Desc']; Rows = [System.Collections.Generic.List[string]]::new() }
    }
    foreach ($f in $files) { $fileContents[$outFile]['Rows'].Add($f) }
}

foreach ($outFile in $fileContents.Keys) {
    $data = $fileContents[$outFile]
    $sb   = [System.Text.StringBuilder]::new()

    if ($data['Title']) {
        $sb.AppendLine("# $($data['Title'])") | Out-Null
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine($data['Desc']) | Out-Null
        $sb.AppendLine("") | Out-Null
    }
    $sb.AppendLine($STATUS_LEGEND) | Out-Null
    $sb.AppendLine("## Files") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("| Status | File | Notes |") | Out-Null
    $sb.AppendLine("|--------|------|-------|") | Out-Null

    foreach ($f in ($data['Rows'] | Sort-Object)) {
        $sb.AppendLine("| ``[ ]`` | $f | |") | Out-Null
    }
    $sb.AppendLine("") | Out-Null

    $outPath = [IO.Path]::GetFullPath([IO.Path]::Combine($OutputDir, $outFile))
    [IO.File]::WriteAllText($outPath, $sb.ToString(), [Text.Encoding]::UTF8)
    Write-Host "Written: $outFile ($($data['Rows'].Count) files)"
}

Write-Host "Done."
