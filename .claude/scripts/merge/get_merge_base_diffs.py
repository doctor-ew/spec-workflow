#!/usr/bin/env python3
"""get_merge_base_diffs.py
For flagged files, outputs compact per-file diffs showing what each branch changed
relative to the merge base, plus commit messages explaining why.
Read-only — never modifies source files.
Python port of Get-MergeBaseDiffs.ps1. Stdlib only.

Usage:
    python3 get_merge_base_diffs.py --file path/to/file.csproj [--repo PATH] [--planning-dir PATH] [--merge-base SHA]
    python3 get_merge_base_diffs.py --help
"""

import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def git_output(args: list[str], cwd: str) -> str:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return result.stdout.strip()


def get_diff(repo: str, from_ref: str, to_ref: str, file: str) -> str:
    return git_output(['git', 'diff', from_ref, to_ref, '--', file], cwd=repo)


def get_log(repo: str, from_ref: str, to_ref: str, file: str) -> str:
    return git_output(['git', 'log', '--oneline', f'{from_ref}..{to_ref}', '--', file], cwd=repo)


def write_file_diff(repo: str, file_path: str, merge_base: str, output_file: Path):
    rc_diff = get_diff(repo, merge_base, 'HEAD', file_path)
    dev_diff = get_diff(repo, merge_base, 'MERGE_HEAD', file_path)
    rc_log = get_log(repo, merge_base, 'HEAD', file_path)
    dev_log = get_log(repo, merge_base, 'MERGE_HEAD', file_path)
    generated = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    sb = []
    sb.append(f'## {file_path}')
    sb.append('')
    sb.append(f'**Generated:** {generated}')
    sb.append('')
    sb.append('### RC commits (HEAD since merge base)')
    sb.append('```')
    sb.append(rc_log if rc_log else '(none)')
    sb.append('```')
    sb.append('')
    sb.append('### Dev commits (MERGE_HEAD since merge base)')
    sb.append('```')
    sb.append(dev_log if dev_log else '(none)')
    sb.append('```')
    sb.append('')
    sb.append('### RC changes (diff merge-base -> HEAD)')
    sb.append('```diff')
    sb.append(rc_diff if rc_diff else '(no changes)')
    sb.append('```')
    sb.append('')
    sb.append('### Dev changes (diff merge-base -> MERGE_HEAD)')
    sb.append('```diff')
    sb.append(dev_diff if dev_diff else '(no changes)')
    sb.append('```')
    sb.append('')
    sb.append('---')
    sb.append('')

    with output_file.open('a', encoding='utf-8') as f:
        f.write('\n'.join(sb) + '\n')

    print(f'  Diff written to {output_file}')


def main():
    parser = argparse.ArgumentParser(
        description='Generate merge-base diffs for a flagged file'
    )
    parser.add_argument('--repo', default='.', help='Path to git repo (default: current directory)')
    parser.add_argument('--file', required=True, help='Relative file path to diff')
    parser.add_argument('--planning-dir', default='./merge-planning', help='Planning directory (default: ./merge-planning)')
    parser.add_argument('--merge-base', default='', help='Merge base SHA (auto-detected if omitted)')
    parser.add_argument('--output', default='', help='Output file path (auto-derived from --file if omitted)')
    args = parser.parse_args()

    repo = str(Path(args.repo).resolve())
    planning_dir = Path(args.planning_dir).resolve()
    flagged_dir = planning_dir / 'FlaggedDiffs'
    flagged_dir.mkdir(parents=True, exist_ok=True)

    merge_base = args.merge_base
    if not merge_base:
        result = subprocess.run(
            ['git', 'merge-base', 'HEAD', 'MERGE_HEAD'],
            cwd=repo, capture_output=True, text=True
        )
        lines = [l for l in result.stdout.splitlines() if l.strip()]
        if len(lines) == 1:
            merge_base = lines[0]
        else:
            print('ERROR: Could not auto-detect merge base. Supply --merge-base.', file=sys.stderr)
            sys.exit(1)

    output_file = Path(args.output) if args.output else flagged_dir / (args.file.replace('/', '_').replace('\\', '_') + '.md')

    write_file_diff(repo, args.file, merge_base, output_file)


if __name__ == '__main__':
    main()
