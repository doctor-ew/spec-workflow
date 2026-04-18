# Merge-Lib.ps1 - Shared helper functions for merge resolution scripts.
# Dot-source this file: . "$PSScriptRoot\Merge-Lib.ps1"
# Parameterised version — no hardcoded paths or SHAs.

# --- Conflict block parsing ---

function Get-ConflictBlocks {
    param([string]$Content)
    $pattern = '(?s)<<<<<<< [^\r\n]+\r?\n(.*?)\r?\n=======\r?\n(.*?)\r?\n>>>>>>> [^\r\n]+'
    $rxm = [regex]::Match($Content, $pattern)
    while ($rxm.Success) {
        @{
            FullMatch = $rxm.Value
            Ours      = $rxm.Groups[1].Value
            Theirs    = $rxm.Groups[2].Value
        }
        $rxm = $rxm.NextMatch()
    }
}

# --- File type detection ---

function Get-FileType {
    param([string]$FilePath)
    $name = [IO.Path]::GetFileName($FilePath).ToLower()
    $ext  = [IO.Path]::GetExtension($FilePath).ToLower()
    if ($name -eq 'packages.config') { return 'packages.config' }
    if ($ext -eq '.nuspec')          { return 'nuspec' }
    if ($ext -eq '.csproj')          { return 'csproj' }
    return 'unknown'
}

# --- Package entry extraction ---

function Get-PackageEntries {
    param([string]$Text, [string]$FileType)
    $entries = @{}

    switch ($FileType) {
        'packages.config' {
            $pattern = '[ \t]*<package\s+id="([^"]+)"\s+version="([^"]+)"[^/]*/>'
            foreach ($m in [regex]::Matches($Text, $pattern)) {
                $id = $m.Groups[1].Value
                $ver = $m.Groups[2].Value
                $entries[$id] = @{ Version = $ver; Block = $m.Value }
            }
        }
        'nuspec' {
            $pattern = '[ \t]*<dependency\s+id="([^"]+)"\s+version="([^"]+)"[^/]*/>'
            foreach ($m in [regex]::Matches($Text, $pattern)) {
                $id = $m.Groups[1].Value
                $ver = $m.Groups[2].Value
                $entries[$id] = @{ Version = $ver; Block = $m.Value }
            }
        }
        'csproj' {
            $pattern1 = '[ \t]*<PackageReference\s+Include="([^"]+)"\s+Version="([^"]+)"[^/]*/>'
            foreach ($m in [regex]::Matches($Text, $pattern1)) {
                $id = $m.Groups[1].Value
                $ver = $m.Groups[2].Value
                $entries[$id] = @{ Version = $ver; Block = $m.Value }
            }
            $pattern2 = '(?s)[ \t]*<PackageReference\s+Include="([^"]+)"[^>]*>.*?</PackageReference>'
            foreach ($m in [regex]::Matches($Text, $pattern2)) {
                $id = $m.Groups[1].Value
                if ($entries.ContainsKey($id)) { continue }
                $verMatch = [regex]::Match($m.Value, '<Version>([^<]+)</Version>')
                if ($verMatch.Success) {
                    $entries[$id] = @{ Version = $verMatch.Groups[1].Value; Block = $m.Value }
                }
            }
            $pattern3 = '(?s)[ \t]*<Reference\s+Include="([^,"]+)[^"]*"[^>]*>(?:(?!<Reference).)*?packages\\[^>]+?</Reference>'
            foreach ($m in [regex]::Matches($Text, $pattern3)) {
                $id = $m.Groups[1].Value.Trim()
                if ($entries.ContainsKey($id)) { continue }
                $verMatch = [regex]::Match($m.Value, 'Version=([\d\.]+)')
                if ($verMatch.Success) {
                    $entries[$id] = @{ Version = $verMatch.Groups[1].Value; Block = $m.Value }
                }
            }
        }
    }
    return $entries
}

# --- csproj HintPath-based conflict resolution ---

function Resolve-CsprojBlock {
    param([string]$OursText, [string]$TheirsText, [switch]$OursWins)

    $result = @{
        ShouldFlag  = $false
        FlagReasons = [System.Collections.Generic.List[string]]::new()
        Decisions   = [System.Collections.Generic.List[hashtable]]::new()
        Resolved    = $null
    }

    $hintPattern = '(?i)<HintPath>[^<]*\\packages\\([^\\]+)\\(?:[^\\]+\\)*([^<\\]+\.dll)</HintPath>'

    function Parse-HintPaths([string]$Text) {
        $map = @{}
        foreach ($m in [regex]::Matches($Text, $hintPattern)) {
            $folder  = $m.Groups[1].Value
            $dll     = $m.Groups[2].Value
            $map[$dll] = @{ PackageFolder = $folder; Line = $m.Value.Trim() }
        }
        return $map
    }

    function Split-PackageFolder([string]$Folder) {
        $parts = $Folder -split '\.'
        $verStart = -1
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -match '^\d') { $verStart = $i; break }
        }
        if ($verStart -le 0) { return $null }
        $pkgId = ($parts[0..($verStart - 1)]) -join '.'
        $ver   = ($parts[$verStart..($parts.Count - 1)]) -join '.'
        return @{ Id = $pkgId; Version = $ver }
    }

    $oursMap   = Parse-HintPaths $OursText
    $theirsMap = Parse-HintPaths $TheirsText

    if ($oursMap.Count -eq 0 -and $theirsMap.Count -eq 0) {
        $result.ShouldFlag = $true
        $result.FlagReasons.Add('No HintPath entries found in either OURS or THEIRS')
        return $result
    }

    $ourDlls    = $oursMap.Keys   | Sort-Object
    $theirDlls  = $theirsMap.Keys | Sort-Object
    $onlyOurs   = $ourDlls   | Where-Object { -not $theirsMap.ContainsKey($_) }
    $onlyTheirs = $theirDlls | Where-Object { -not $oursMap.ContainsKey($_) }

    if ($onlyOurs.Count -gt 0 -or $onlyTheirs.Count -gt 0) {
        $result.ShouldFlag = $true
        $result.FlagReasons.Add("Complex conflict. Manual review required.")
        return $result
    }

    foreach ($dll in $ourDlls) {
        $ourPkg   = Split-PackageFolder $oursMap[$dll].PackageFolder
        $theirPkg = Split-PackageFolder $theirsMap[$dll].PackageFolder

        if ($null -eq $ourPkg -or $null -eq $theirPkg) {
            $result.ShouldFlag = $true
            $result.FlagReasons.Add("Could not parse package folder for DLL: $dll")
            return $result
        }

        if ($ourPkg.Id -ne $theirPkg.Id) {
            $result.ShouldFlag = $true
            $result.FlagReasons.Add("Complex conflict. Manual review required.")
            return $result
        }

        $pkgId  = $theirPkg.Id
        $ourVer = $ourPkg.Version
        $thrVer = $theirPkg.Version

        $ourParts = $ourVer -split '\.'
        $thrParts = $thrVer -split '\.'
        if ($ourParts.Count -gt 4 -or $thrParts.Count -gt 4) {
            if ($ourParts.Count -le 4 -or $thrParts.Count -le 4) {
                $result.ShouldFlag = $true
                $result.FlagReasons.Add("${pkgId}: mixed version format ('$ourVer' vs '$thrVer') -- manual review required")
                return $result
            }
            $ourPrefix = ($ourParts[0..2]) -join '.'
            $thrPrefix = ($thrParts[0..2]) -join '.'
            if ($ourPrefix -ne $thrPrefix) {
                $result.ShouldFlag = $true
                $result.FlagReasons.Add("${pkgId}: framework version mismatch ($ourPrefix vs $thrPrefix) -- manual review required")
                return $result
            }
            $ourVer = ($ourParts[3..($ourParts.Count - 1)]) -join '.'
            $thrVer = ($thrParts[3..($thrParts.Count - 1)]) -join '.'
        }

        $cmp = Compare-NuGetVersions $ourVer $thrVer

        if ($null -eq $cmp) {
            $result.ShouldFlag = $true
            $result.FlagReasons.Add("${pkgId}: unparseable versions '$ourVer' vs '$thrVer'")
            return $result
        }

        if ($cmp -eq 0) {
            $result.Decisions.Add(@{ Package = $pkgId; Ours = $ourVer; Theirs = $thrVer; Resolution = 'Same version -- kept' })
        } elseif (($cmp -gt 0 -and -not $OursWins) -or ($cmp -lt 0 -and $OursWins)) {
            # Preferred side is lower -- unusual
            $result.ShouldFlag = $true
            $result.FlagReasons.Add("${pkgId}: HEAD ($ourVer) > MERGE_HEAD ($thrVer) -- verify this is intentional")
        } else {
            $winner = if ($OursWins) { 'RC (higher)' } else { 'Dev (higher)' }
            $result.Decisions.Add(@{ Package = $pkgId; Ours = $ourVer; Theirs = $thrVer; Resolution = "Took $winner" })
        }
    }

    if (-not $result.ShouldFlag) {
        $result.Resolved = if ($OursWins) { $OursText } else { $TheirsText }
    }
    return $result
}

# --- Non-package content detection ---

function Test-HasNonPackageContent {
    param([string]$Text, [string]$FileType)
    if ($FileType -ne 'csproj') { return $false }
    $flags = @(
        '<TargetFramework', '<AssemblyName', '<RootNamespace', '<OutputType',
        '<ProjectReference', '<Compile ', '<Content ', '<None ', '<Import ',
        '<Target ', '<PropertyGroup'
    )
    foreach ($f in $flags) {
        if ($Text.IndexOf($f, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    $hasPackages = ($Text -match '<PackageReference|<Reference\s+Include=')
    return -not $hasPackages
}

# --- Version comparison ---

function Compare-NuGetVersions {
    param([string]$V1, [string]$V2)
    $clean1 = $V1 -replace '-.*$', ''
    $clean2 = $V2 -replace '-.*$', ''
    try {
        $ver1 = [System.Version]::Parse($clean1)
        $ver2 = [System.Version]::Parse($clean2)
        $cmp = $ver1.CompareTo($ver2)
        if ($cmp -eq 0 -and $V1 -ne $V2) { return [string]::Compare($V1, $V2) }
        return $cmp
    } catch {
        return $null
    }
}

# --- Decision ID management ---

function Get-NextDecisionId {
    param([string]$DecisionsDir)
    if (-not (Test-Path $DecisionsDir)) { return 'D-001' }
    $files = Get-ChildItem $DecisionsDir -Filter 'D-*.md'
    if ($files.Count -eq 0) { return 'D-001' }
    $max = $files | ForEach-Object {
        if ($_.Name -match 'D-(\d+)\.md') { [int]$Matches[1] }
    } | Measure-Object -Maximum
    return 'D-{0:D3}' -f ([int]$max.Maximum + 1)
}

# --- Phase file status update ---

function Update-PhaseFileStatus {
    param([string]$PhaseFilePath, [string]$RelativeFilePath, [string]$NewStatus)
    if ([string]::IsNullOrWhiteSpace($RelativeFilePath)) { throw "Update-PhaseFileStatus: RelativeFilePath cannot be empty" }
    if ([string]::IsNullOrWhiteSpace($NewStatus))        { throw "Update-PhaseFileStatus: NewStatus cannot be empty" }
    $content = [IO.File]::ReadAllText($PhaseFilePath)
    $escaped = [regex]::Escape($RelativeFilePath)
    $pattern = '(\| `)(\[ \]|\[>\]|\[!\]|\[x\])(`( \|.*?' + $escaped + '))'
    $replacement = "`${1}$NewStatus`${3}"
    $updated = [regex]::Replace($content, $pattern, $replacement)
    if ($updated -ne $content) {
        [IO.File]::WriteAllText($PhaseFilePath, $updated, [Text.Encoding]::UTF8)
        return $true
    }
    return $false
}
