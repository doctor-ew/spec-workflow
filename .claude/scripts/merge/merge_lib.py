"""merge_lib.py — Shared helper functions for merge resolution scripts.
Python port of Merge-Lib.ps1. Stdlib only — no pip installs required.
"""

import re
import os
import subprocess
from datetime import datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Conflict block parsing
# ---------------------------------------------------------------------------

CONFLICT_PATTERN = re.compile(
    r'<<<<<<< [^\r\n]+\r?\n(.*?)\r?\n=======\r?\n(.*?)\r?\n>>>>>>> [^\r\n]+',
    re.DOTALL
)


def get_conflict_blocks(content: str) -> list[dict]:
    """Return list of dicts: {full_match, ours, theirs}."""
    results = []
    for m in CONFLICT_PATTERN.finditer(content):
        results.append({
            'full_match': m.group(0),
            'ours': m.group(1),
            'theirs': m.group(2),
        })
    return results


# ---------------------------------------------------------------------------
# File type detection
# ---------------------------------------------------------------------------

def get_file_type(file_path: str) -> str:
    name = os.path.basename(file_path).lower()
    _, ext = os.path.splitext(name)
    if name == 'packages.config':
        return 'packages.config'
    if ext == '.nuspec':
        return 'nuspec'
    if ext == '.csproj':
        return 'csproj'
    return 'unknown'


# ---------------------------------------------------------------------------
# Package entry extraction
# Returns: dict of PackageId -> {version, block}
# ---------------------------------------------------------------------------

def get_package_entries(text: str, file_type: str) -> dict:
    entries = {}

    if file_type == 'packages.config':
        pattern = re.compile(
            r'[ \t]*<package\s+id="([^"]+)"\s+version="([^"]+)"[^/]*/>'
        )
        for m in pattern.finditer(text):
            pkg_id, ver = m.group(1), m.group(2)
            entries[pkg_id] = {'version': ver, 'block': m.group(0)}

    elif file_type == 'nuspec':
        pattern = re.compile(
            r'[ \t]*<dependency\s+id="([^"]+)"\s+version="([^"]+)"[^/]*/>'
        )
        for m in pattern.finditer(text):
            pkg_id, ver = m.group(1), m.group(2)
            entries[pkg_id] = {'version': ver, 'block': m.group(0)}

    elif file_type == 'csproj':
        # New-style single-line PackageReference
        p1 = re.compile(
            r'[ \t]*<PackageReference\s+Include="([^"]+)"\s+Version="([^"]+)"[^/]*/>'
        )
        for m in p1.finditer(text):
            pkg_id, ver = m.group(1), m.group(2)
            entries[pkg_id] = {'version': ver, 'block': m.group(0)}

        # New-style multi-line PackageReference
        p2 = re.compile(
            r'[ \t]*<PackageReference\s+Include="([^"]+)"[^>]*>.*?</PackageReference>',
            re.DOTALL
        )
        for m in p2.finditer(text):
            pkg_id = m.group(1)
            if pkg_id in entries:
                continue
            ver_m = re.search(r'<Version>([^<]+)</Version>', m.group(0))
            if ver_m:
                entries[pkg_id] = {'version': ver_m.group(1), 'block': m.group(0)}

        # Old-style Reference with HintPath
        p3 = re.compile(
            r'[ \t]*<Reference\s+Include="([^,"]+)[^"]*"[^>]*>(?:(?!<Reference).)*?packages\\[^>]+?</Reference>',
            re.DOTALL
        )
        for m in p3.finditer(text):
            pkg_id = m.group(1).strip()
            if pkg_id in entries:
                continue
            ver_m = re.search(r'Version=([\d\.]+)', m.group(0))
            if ver_m:
                entries[pkg_id] = {'version': ver_m.group(1), 'block': m.group(0)}

    return entries


# ---------------------------------------------------------------------------
# csproj HintPath-based conflict resolution
# ---------------------------------------------------------------------------

HINT_PATTERN = re.compile(
    r'(?i)<HintPath>[^<]*[/\\]packages[/\\]([^/\\]+)[/\\](?:[^/\\]+[/\\])*([^<\\/]+\.dll)</HintPath>'
)


def _parse_hint_paths(text: str) -> dict:
    """Returns dict: dll_name -> {package_folder, line}."""
    result = {}
    for m in HINT_PATTERN.finditer(text):
        folder = m.group(1)
        dll = m.group(2)
        result[dll] = {'package_folder': folder, 'line': m.group(0).strip()}
    return result


def _split_package_folder(folder: str):
    """Split 'SomePkg.Name.1.2.3.4' into (id, version). Returns None if unparseable."""
    parts = folder.split('.')
    ver_start = -1
    for i, p in enumerate(parts):
        if p and p[0].isdigit():
            ver_start = i
            break
    if ver_start <= 0:
        return None
    pkg_id = '.'.join(parts[:ver_start])
    ver = '.'.join(parts[ver_start:])
    return {'id': pkg_id, 'version': ver}


def resolve_csproj_block(ours_text: str, theirs_text: str, theirs_wins: bool = True) -> dict:
    """Port of Resolve-CsprojBlock. Returns {should_flag, flag_reasons, decisions, resolved}."""
    result = {
        'should_flag': False,
        'flag_reasons': [],
        'decisions': [],
        'resolved': None,
    }

    ours_map = _parse_hint_paths(ours_text)
    theirs_map = _parse_hint_paths(theirs_text)

    if not ours_map and not theirs_map:
        result['should_flag'] = True
        result['flag_reasons'].append('No HintPath entries found in either OURS or THEIRS')
        return result

    our_dlls = set(ours_map.keys())
    their_dlls = set(theirs_map.keys())
    only_ours = our_dlls - their_dlls
    only_theirs = their_dlls - our_dlls

    if only_ours or only_theirs:
        result['should_flag'] = True
        result['flag_reasons'].append('Complex conflict. Manual review required.')
        return result

    for dll in sorted(our_dlls):
        our_pkg = _split_package_folder(ours_map[dll]['package_folder'])
        their_pkg = _split_package_folder(theirs_map[dll]['package_folder'])

        if our_pkg is None or their_pkg is None:
            result['should_flag'] = True
            result['flag_reasons'].append(f'Could not parse package folder for DLL: {dll}')
            return result

        if our_pkg['id'] != their_pkg['id']:
            result['should_flag'] = True
            result['flag_reasons'].append('Complex conflict. Manual review required.')
            return result

        pkg_id = their_pkg['id']
        our_ver = our_pkg['version']
        their_ver = their_pkg['version']

        our_parts = our_ver.split('.')
        their_parts = their_ver.split('.')

        if len(our_parts) > 4 or len(their_parts) > 4:
            if len(our_parts) <= 4 or len(their_parts) <= 4:
                result['should_flag'] = True
                result['flag_reasons'].append(
                    f"{pkg_id}: mixed version format ('{our_ver}' vs '{their_ver}') -- manual review required"
                )
                return result
            our_prefix = '.'.join(our_parts[:3])
            their_prefix = '.'.join(their_parts[:3])
            if our_prefix != their_prefix:
                result['should_flag'] = True
                result['flag_reasons'].append(
                    f"{pkg_id}: framework version mismatch ({our_prefix} vs {their_prefix}) -- manual review required"
                )
                return result
            our_ver = '.'.join(our_parts[3:])
            their_ver = '.'.join(their_parts[3:])

        cmp = compare_nuget_versions(our_ver, their_ver)

        if cmp is None:
            result['should_flag'] = True
            result['flag_reasons'].append(f"{pkg_id}: unparseable versions '{our_ver}' vs '{their_ver}'")
            return result

        if cmp == 0:
            result['decisions'].append({'package': pkg_id, 'ours': our_ver, 'theirs': their_ver, 'resolution': 'Same version -- kept'})
        elif (cmp > 0 and theirs_wins) or (cmp < 0 and not theirs_wins):
            # Preferred side is lower -- unusual
            result['should_flag'] = True
            result['flag_reasons'].append(
                f"{pkg_id}: HEAD ({our_ver}) > MERGE_HEAD ({their_ver}) -- verify this is intentional"
            )
        else:
            result['decisions'].append({'package': pkg_id, 'ours': our_ver, 'theirs': their_ver, 'resolution': 'Took preferred (higher)'})

    if not result['should_flag']:
        result['resolved'] = theirs_text if theirs_wins else ours_text
    return result


# ---------------------------------------------------------------------------
# Non-package content detection
# ---------------------------------------------------------------------------

NON_PACKAGE_FLAGS = [
    '<TargetFramework', '<AssemblyName', '<RootNamespace', '<OutputType',
    '<ProjectReference', '<Compile ', '<Content ', '<None ', '<Import ',
    '<Target ', '<PropertyGroup',
]


def test_has_non_package_content(text: str, file_type: str) -> bool:
    if file_type != 'csproj':
        return False
    for flag in NON_PACKAGE_FLAGS:
        if flag.lower() in text.lower():
            return True
    has_packages = bool(re.search(r'<PackageReference|<Reference\s+Include=', text, re.IGNORECASE))
    return not has_packages


# ---------------------------------------------------------------------------
# Version comparison
# Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal, None if unparseable
# ---------------------------------------------------------------------------

def compare_nuget_versions(v1: str, v2: str):
    def parse_ver(v: str):
        clean = re.sub(r'-.*$', '', v)
        parts = clean.split('.')
        try:
            return tuple(int(p) for p in parts)
        except ValueError:
            return None

    p1 = parse_ver(v1)
    p2 = parse_ver(v2)
    if p1 is None or p2 is None:
        return None

    # Pad to same length
    max_len = max(len(p1), len(p2))
    p1 = p1 + (0,) * (max_len - len(p1))
    p2 = p2 + (0,) * (max_len - len(p2))

    if p1 > p2:
        return 1
    if p1 < p2:
        return -1
    # Equal numeric parts — compare pre-release suffixes
    if v1 != v2:
        return (v1 > v2) - (v1 < v2)
    return 0


# ---------------------------------------------------------------------------
# Decision ID management
# ---------------------------------------------------------------------------

def get_next_decision_id(decisions_dir: Path) -> str:
    if not decisions_dir.exists():
        return 'D-001'
    existing = list(decisions_dir.glob('D-*.md'))
    if not existing:
        return 'D-001'
    nums = []
    for f in existing:
        m = re.match(r'D-(\d+)\.md', f.name)
        if m:
            nums.append(int(m.group(1)))
    if not nums:
        return 'D-001'
    return f'D-{max(nums) + 1:03d}'


# ---------------------------------------------------------------------------
# Phase file status update
# ---------------------------------------------------------------------------

def update_phase_file_status(phase_file_path: Path, relative_file_path: str, new_status: str) -> bool:
    """Updates the status cell for a given file row in a phase markdown file."""
    content = phase_file_path.read_text(encoding='utf-8')
    escaped = re.escape(relative_file_path)
    pattern = re.compile(
        r'(\| `)(\[ \]|\[>\]|\[!\]|\[x\])(`( \|.*?' + escaped + r'))'
    )
    updated = pattern.sub(lambda m: f"{m.group(1)}{new_status}{m.group(3)}", content)
    if updated != content:
        phase_file_path.write_text(updated, encoding='utf-8')
        return True
    return False


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def git(args: list[str], cwd: str = '.') -> str:
    """Run git command, return stdout as string."""
    result = subprocess.run(
        ['git'] + args,
        cwd=cwd,
        capture_output=True,
        text=True
    )
    return result.stdout.strip()


def get_merge_base(repo: str) -> str | None:
    """Auto-detect merge base. Returns None if ambiguous or not in a merge."""
    output = git(['merge-base', 'HEAD', 'MERGE_HEAD'], cwd=repo)
    lines = [l for l in output.splitlines() if l.strip()]
    if len(lines) == 1:
        return lines[0]
    return None


def now_str() -> str:
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')
