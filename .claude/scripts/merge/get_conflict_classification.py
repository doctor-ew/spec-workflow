#!/usr/bin/env python3
"""get_conflict_classification.py
Classifies UU and AA conflicts by file type.
Python port of Get-ConflictClassification.ps1. Stdlib only.

Usage:
    python3 get_conflict_classification.py [--repo PATH] [--planning-dir PATH]
    python3 get_conflict_classification.py --help
"""

import argparse
import subprocess
import sys
from collections import OrderedDict
from datetime import datetime
from pathlib import Path


# Extension-to-group mapping (ordered — first match wins)
EXT_GROUPS = OrderedDict([
    ('Packages',   ['.csproj', '.nuspec']),
    ('Config',     ['.config']),
    ('Pipeline',   ['.yml', '.yaml']),
    ('CSharp',     ['.cs']),
    ('JavaScript', ['.js']),
    ('Views',      ['.cshtml']),
    ('Other',      []),  # catch-all
])

FILENAME_GROUPS = {
    'Packages': ['packages.config'],
}


def get_group(file: str) -> str:
    name = Path(file).name.lower()
    ext = Path(file).suffix.lower()

    for group, names in FILENAME_GROUPS.items():
        if name in names:
            return group
    for group, exts in EXT_GROUPS.items():
        if ext in exts:
            return group
    return 'Other'


def main():
    parser = argparse.ArgumentParser(
        description='Classify git merge conflicts into ConflictClassification.md'
    )
    parser.add_argument('--repo', default='.', help='Path to git repo (default: current directory)')
    parser.add_argument('--planning-dir', default='./merge-planning', help='Output directory (default: ./merge-planning)')
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    planning_dir = Path(args.planning_dir).resolve()
    output_path = planning_dir / 'ConflictClassification.md'

    # --- Collect status ---
    result = subprocess.run(
        ['git', 'status', '--porcelain'],
        cwd=str(repo),
        capture_output=True,
        text=True
    )
    lines = result.stdout.splitlines()

    if not lines:
        print('ERROR: No output from git status. Verify repo path and that a merge is in progress.', file=sys.stderr)
        sys.exit(1)

    uu = []
    aa = []

    for line in lines:
        if len(line) < 4:
            continue
        code = line[:2].strip()
        file = line[3:].strip()
        if code == 'UU':
            uu.append(file)
        elif code == 'AA':
            aa.append(file)

    # --- Classify UU by group ---
    groups = {k: [] for k in EXT_GROUPS}
    for file in uu:
        group = get_group(file)
        groups[group].append(file)

    # --- Build output ---
    generated = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    sb = []
    sb.append('# Conflict Classification')
    sb.append('')
    sb.append(f'**Generated:** {generated}')
    sb.append('')
    sb.append('## Summary')
    sb.append('')
    sb.append('| Group | Count |')
    sb.append('|-------|-------|')
    for key in EXT_GROUPS:
        sb.append(f'| UU / {key} | {len(groups[key])} |')
    sb.append(f'| AA / Both-added | {len(aa)} |')
    sb.append(f'| **Total** | **{len(uu) + len(aa)}** |')
    sb.append('')

    for key in EXT_GROUPS:
        files = sorted(groups[key])
        if not files:
            continue
        sb.append(f'## UU / {key} - {len(files)} file(s)')
        sb.append('')
        for f in files:
            sb.append(f'- {f}')
        sb.append('')

    if aa:
        sb.append(f'## AA / Both-added - {len(aa)} file(s)')
        sb.append('')
        for f in sorted(aa):
            sb.append(f'- {f}')
        sb.append('')

    # --- Write output ---
    planning_dir.mkdir(parents=True, exist_ok=True)
    output_path.write_text('\n'.join(sb) + '\n', encoding='utf-8')
    print(f'Done. {len(uu) + len(aa)} conflict(s) classified. Output: {output_path}')


if __name__ == '__main__':
    main()
