#!/usr/bin/env python3
"""get_conflict_list.py
Reads git status --porcelain from a repo with a merge in progress
and writes a structured conflict list to the planning directory.

Python port of Get-ConflictList.ps1. Stdlib only.

Usage:
    python3 get_conflict_list.py [--repo PATH] [--planning-dir PATH]
    python3 get_conflict_list.py --help
"""

import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path


CATEGORY_LABELS = {
    'UU': 'Both modified',
    'AA': 'Both added',
    'DD': 'Both deleted',
    'AU': 'Added by us',
    'UA': 'Added by them',
    'DU': 'Deleted by us',
    'UD': 'Deleted by them',
}
CATEGORY_ORDER = ['UU', 'AA', 'DD', 'AU', 'UA', 'DU', 'UD']


def main():
    parser = argparse.ArgumentParser(
        description='List git merge conflicts into ConflictList.md'
    )
    parser.add_argument('--repo', default='.', help='Path to git repo (default: current directory)')
    parser.add_argument('--planning-dir', default='./merge-planning', help='Output directory (default: ./merge-planning)')
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    planning_dir = Path(args.planning_dir).resolve()
    output_path = planning_dir / 'ConflictList.md'

    # --- Collect raw status ---
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

    # --- Parse into conflict categories ---
    categories = {code: [] for code in CATEGORY_ORDER}
    unrecognized = []

    for line in lines:
        if len(line) < 4:
            continue
        code = line[:2].strip()
        file = line[3:].strip()
        if code in categories:
            categories[code].append(file)
        else:
            unrecognized.append(f'[{code}] {file}')

    # --- Build output ---
    generated = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    total = sum(len(v) for v in categories.values())

    sb = []
    sb.append('# Conflict List')
    sb.append('')
    sb.append(f'**Generated:** {generated}')
    sb.append(f'**Repo:** {repo}')
    sb.append('')
    sb.append('## Summary')
    sb.append('')
    sb.append('| Code | Meaning | Count |')
    sb.append('|------|---------|-------|')
    for code in CATEGORY_ORDER:
        sb.append(f'| {code} | {CATEGORY_LABELS[code]} | {len(categories[code])} |')
    sb.append(f'| **Total** | | **{total}** |')
    sb.append('')

    for code in CATEGORY_ORDER:
        files = sorted(categories[code])
        if not files:
            continue
        sb.append(f'## {code} - {len(files)} file(s)')
        sb.append('')
        for f in files:
            sb.append(f'- {f}')
        sb.append('')

    if unrecognized:
        sb.append('## Unrecognized codes')
        sb.append('')
        for f in unrecognized:
            sb.append(f'- {f}')
        sb.append('')

    # --- Write output ---
    planning_dir.mkdir(parents=True, exist_ok=True)
    output_path.write_text('\n'.join(sb) + '\n', encoding='utf-8')
    print(f'Done. {total} conflict(s) written to: {output_path}')


if __name__ == '__main__':
    main()
