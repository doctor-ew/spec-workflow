#!/usr/bin/env python3
"""validate_resolved.py
Scans [x]-marked files for remaining conflict markers and structural issues.
Python port of _ValidateResolved.ps1. Stdlib only.

Usage:
    python3 validate_resolved.py --repo PATH [--phase-file PATH] [--planning-dir PATH] [--all-phases]
    python3 validate_resolved.py --help
"""

import argparse
import re
import sys
from pathlib import Path


CONFLICT_MARKER = re.compile(r'<<<<<<<|>>>>>>>')


def get_resolved_files(phase_file: Path) -> list[str]:
    """Return files marked [x] in a phase file."""
    content = phase_file.read_text(encoding='utf-8')
    return [
        m.group(1).strip()
        for m in re.finditer(r'\| `\[x\]` \| ([^|]+) \|', content)
    ]


def validate_phase_file(phase_file: Path, repo: Path) -> list[str]:
    issues = []
    resolved = get_resolved_files(phase_file)

    for rel in resolved:
        full = repo / rel
        if not full.exists():
            continue

        text = full.read_text(encoding='utf-8')
        name = full.name.lower()
        ext = full.suffix.lower()

        if name == 'packages.config' and '</packages>' not in text:
            issues.append(f'MISSING </packages>: {rel}')
        if ext == '.nuspec' and '</dependencies>' not in text:
            issues.append(f'MISSING </dependencies>: {rel}')
        if CONFLICT_MARKER.search(text):
            issues.append(f'CONFLICT MARKERS REMAIN: {rel}')

    return issues


def main():
    parser = argparse.ArgumentParser(description='Validate resolved files for remaining conflict markers')
    parser.add_argument('--repo', default='.', help='Path to git repo (default: current directory)')
    parser.add_argument('--phase-file', help='Single phase file to validate')
    parser.add_argument('--planning-dir', default='./merge-planning', help='Planning directory (default: ./merge-planning)')
    parser.add_argument('--all-phases', action='store_true', help='Validate all Phase-*.md files in planning-dir')
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    planning_dir = Path(args.planning_dir).resolve()

    phase_files = []

    if args.all_phases:
        phase_files = sorted(planning_dir.glob('Phase-*.md'))
        if not phase_files:
            print(f'No Phase-*.md files found in {planning_dir}')
            sys.exit(0)
    elif args.phase_file:
        phase_files = [Path(args.phase_file)]
    else:
        # Default to Phase-1-Packages.md
        default = planning_dir / 'Phase-1-Packages.md'
        if not default.exists():
            print(f'ERROR: {default} not found. Specify --phase-file or --all-phases.', file=sys.stderr)
            sys.exit(1)
        phase_files = [default]

    all_issues = []
    total_checked = 0

    for pf in phase_files:
        if not pf.exists():
            print(f'WARNING: {pf} not found, skipping.')
            continue
        issues = validate_phase_file(pf, repo)
        resolved_count = len(get_resolved_files(pf))
        total_checked += resolved_count
        if issues:
            all_issues.extend(issues)

    if not all_issues:
        print(f'All {total_checked} resolved file(s) OK.')
    else:
        print(f'{len(all_issues)} issue(s) found:')
        for issue in all_issues:
            print(f'  {issue}')
        sys.exit(1)


if __name__ == '__main__':
    main()
