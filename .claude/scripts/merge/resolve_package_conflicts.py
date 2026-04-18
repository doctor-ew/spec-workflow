#!/usr/bin/env python3
"""resolve_package_conflicts.py
Resolves package file conflicts from an in-progress git merge.
HEAD = OURS, MERGE_HEAD = THEIRS (Dev branch by default).
Python port of Resolve-PackageConflicts.ps1. Stdlib only.

Usage:
    python3 resolve_package_conflicts.py --dry-run                 # preview only
    python3 resolve_package_conflicts.py --batch-start 1           # live, first 15 files
    python3 resolve_package_conflicts.py --batch-start 16          # next 15 files
    python3 resolve_package_conflicts.py --ours-wins --dry-run     # HEAD wins
    python3 resolve_package_conflicts.py --help
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

# Adjust import path for merge_lib
sys.path.insert(0, str(Path(__file__).parent))
from merge_lib import (
    get_conflict_blocks, get_file_type, get_package_entries,
    resolve_csproj_block, test_has_non_package_content,
    compare_nuget_versions, get_next_decision_id,
    update_phase_file_status, now_str, git
)


def get_pending_files(phase_file: Path) -> list[str]:
    content = phase_file.read_text(encoding='utf-8')
    return [
        m.group(1).strip()
        for m in re.finditer(r'\| `\[ \]` \| ([^|]+) \|', content)
    ]


def run_merge_base_diffs(repo: Path, file_path: str, planning_dir: Path, merge_base: str):
    """Call get_merge_base_diffs.py for flagged files."""
    script = Path(__file__).parent / 'get_merge_base_diffs.py'
    subprocess.run(
        [sys.executable, str(script),
         '--repo', str(repo),
         '--file', file_path,
         '--planning-dir', str(planning_dir),
         '--merge-base', merge_base],
        check=False
    )


def main():
    parser = argparse.ArgumentParser(description='Resolve package file conflicts from a git merge')
    parser.add_argument('--repo', default='.', help='Path to git repo (default: current directory)')
    parser.add_argument('--phase-file', help='Phase file path (default: <planning-dir>/Phase-1-Packages.md)')
    parser.add_argument('--planning-dir', default='./merge-planning', help='Planning directory (default: ./merge-planning)')
    parser.add_argument('--merge-base', default='', help='Merge base SHA (auto-detected if omitted)')
    parser.add_argument('--batch-start', type=int, default=1, help='Start at file N (1-based, default: 1)')
    parser.add_argument('--batch-size', type=int, default=15, help='Max files per batch (default: 15)')
    parser.add_argument('--dry-run', action='store_true', help='Preview only — no files modified')
    parser.add_argument('--theirs-wins', action='store_true', default=True, help='MERGE_HEAD wins (default)')
    parser.add_argument('--ours-wins', action='store_true', help='HEAD wins')
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    planning_dir = Path(args.planning_dir).resolve()
    phase_file = Path(args.phase_file) if args.phase_file else planning_dir / 'Phase-1-Packages.md'
    theirs_wins = not args.ours_wins

    # Auto-detect merge base
    merge_base = args.merge_base
    if not merge_base:
        merge_base = git(['merge-base', 'HEAD', 'MERGE_HEAD'], cwd=str(repo))
        if '\n' in merge_base:
            print('ERROR: Multiple merge base candidates (criss-cross merge). Supply --merge-base explicitly.', file=sys.stderr)
            sys.exit(1)
        if not merge_base:
            print('ERROR: Could not detect merge base. Are you in a merge?', file=sys.stderr)
            sys.exit(1)

    decisions_dir = planning_dir / 'Decisions' / 'Phase-1'
    if not args.dry_run:
        decisions_dir.mkdir(parents=True, exist_ok=True)

    # --- Read pending files ---
    if not phase_file.exists():
        print(f'ERROR: Phase file not found: {phase_file}', file=sys.stderr)
        sys.exit(1)

    pending = get_pending_files(phase_file)
    if not pending:
        print('No pending files in phase file.')
        return

    batch = pending[args.batch_start - 1: args.batch_start - 1 + args.batch_size]
    print(f'Processing files {args.batch_start} to {args.batch_start + len(batch) - 1} of {len(pending)} pending.')
    if args.dry_run:
        print('[DRY RUN - no files will be modified]')
    print()

    processed = 0

    for rel_path in batch:
        full_path = repo / rel_path
        print(f'--- {rel_path}')

        if not full_path.exists():
            print(f'  File not found: {full_path} -- stopping batch.', file=sys.stderr)
            break

        content = full_path.read_text(encoding='utf-8')
        file_type = get_file_type(rel_path)
        blocks = get_conflict_blocks(content)

        if not blocks:
            print('  No conflict markers -- marking complete.')
            if not args.dry_run:
                update_phase_file_status(phase_file, rel_path, '[x]')
            processed += 1
            print()
            continue

        print(f'  {len(blocks)} conflict block(s) found. File type: {file_type}')

        file_decisions = []
        file_flags = []
        should_flag = False
        resolved_content = content

        for block in blocks:
            if should_flag:
                break

            # Non-package content check
            if (test_has_non_package_content(block['ours'], file_type) or
                    test_has_non_package_content(block['theirs'], file_type)):
                should_flag = True
                file_flags.append('Non-package content detected in conflict block')
                break

            # csproj: HintPath-based resolution
            if file_type == 'csproj':
                result = resolve_csproj_block(block['ours'], block['theirs'], theirs_wins)
                file_decisions.extend(result['decisions'])
                if result['should_flag']:
                    should_flag = True
                    file_flags.extend(result['flag_reasons'])
                    break
                resolved_content = resolved_content.replace(block['full_match'], result['resolved'])
                continue

            # packages.config / nuspec
            our_entries = get_package_entries(block['ours'], file_type)
            their_entries = get_package_entries(block['theirs'], file_type)

            if not our_entries and not their_entries:
                should_flag = True
                file_flags.append('Conflict block contains no recognizable package entries')
                break

            resolved_lines = []
            all_ids = sorted(set(list(our_entries.keys()) + list(their_entries.keys())))

            for pkg_id in all_ids:
                has_ours = pkg_id in our_entries
                has_theirs = pkg_id in their_entries

                if has_ours and has_theirs:
                    our_ver = our_entries[pkg_id]['version']
                    their_ver = their_entries[pkg_id]['version']
                    cmp = compare_nuget_versions(our_ver, their_ver)

                    if cmp is None:
                        should_flag = True
                        file_flags.append(f"  {pkg_id}: unparseable versions '{our_ver}' vs '{their_ver}'")
                        break

                    if cmp == 0:
                        resolved_lines.append(our_entries[pkg_id]['block'])
                        file_decisions.append({'package': pkg_id, 'ours': our_ver, 'theirs': their_ver, 'resolution': 'Same version -- kept'})
                    elif (cmp > 0 and theirs_wins) or (cmp < 0 and not theirs_wins):
                        # Preferred side is lower -- unusual; always take OURS (matches PS1 safety behaviour)
                        resolved_lines.append(our_entries[pkg_id]['block'])
                        resolution = f"Took HEAD (higher) [UNUSUAL: verify]"
                        file_decisions.append({'package': pkg_id, 'ours': our_ver, 'theirs': their_ver, 'resolution': resolution})
                        if cmp > 0:
                            file_flags.append(f"  {pkg_id}: HEAD ({our_ver}) > MERGE_HEAD ({their_ver}) -- preferred side (MERGE_HEAD) is lower, verify this is intentional")
                        else:
                            file_flags.append(f"  {pkg_id}: MERGE_HEAD ({their_ver}) > HEAD ({our_ver}) -- preferred side (HEAD) is lower, verify this is intentional")
                    else:
                        # Preferred side is higher -- normal
                        preferred_block = their_entries[pkg_id]['block'] if theirs_wins else our_entries[pkg_id]['block']
                        resolved_lines.append(preferred_block)
                        winner = 'Dev (higher)' if theirs_wins else 'RC (higher)'
                        file_decisions.append({'package': pkg_id, 'ours': our_ver, 'theirs': their_ver, 'resolution': f'Took {winner}'})
                elif has_ours:
                    resolved_lines.append(our_entries[pkg_id]['block'])
                    file_decisions.append({'package': pkg_id, 'ours': our_entries[pkg_id]['version'], 'theirs': '--', 'resolution': 'HEAD only -- kept'})
                else:
                    resolved_lines.append(their_entries[pkg_id]['block'])
                    file_decisions.append({'package': pkg_id, 'ours': '--', 'theirs': their_entries[pkg_id]['version'], 'resolution': 'MERGE_HEAD only -- kept'})

            if should_flag:
                break

            # Preserve structural closing tags
            closing_tags = {'packages.config': '</packages>', 'nuspec': '</dependencies>'}
            if file_type in closing_tags:
                tag = closing_tags[file_type]
                combined = block['ours'] + '\n' + block['theirs']
                tag_m = re.search(r'[ \t]*' + re.escape(tag), combined)
                if tag_m:
                    resolved_lines.append(tag_m.group(0))

            resolved_block = '\r\n'.join(resolved_lines)
            resolved_content = resolved_content.replace(block['full_match'], resolved_block)

        # --- Output / apply ---
        if should_flag:
            print('  [!] FLAGGED:')
            for f in file_flags:
                print(f'      {f}')
            if not args.dry_run:
                update_phase_file_status(phase_file, rel_path, '[!]')
                run_merge_base_diffs(repo, rel_path, planning_dir, merge_base)
        else:
            print('  Decisions:')
            for d in file_decisions:
                print(f"    {d['package']}: {d['ours']} vs {d['theirs']} -- {d['resolution']}")

            # Strip whitespace-only conflict blocks
            resolved_content = re.sub(
                r'(?s)<<<<<<< [^\r\n]+\r?\n[ \t\r\n]*=======\r?\n[ \t\r\n]*>>>>>>> [^\r\n]+(\r?\n)?',
                '',
                resolved_content
            )

            if re.search(r'<<<<<<< |>>>>>>> ', resolved_content):
                should_flag = True
                file_flags.append('Conflict markers remain after resolution -- replace failed on one or more blocks')

            if args.dry_run:
                print('  [DRY RUN] Would write resolved file.')
            elif should_flag:
                print('  [!] FLAGGED:')
                for f in file_flags:
                    print(f'      {f}')
                update_phase_file_status(phase_file, rel_path, '[!]')
                run_merge_base_diffs(repo, rel_path, planning_dir, merge_base)
            else:
                try:
                    full_path.write_text(resolved_content, encoding='utf-8')
                    subprocess.run(['git', '-C', str(repo), 'add', rel_path], check=True)
                    update_phase_file_status(phase_file, rel_path, '[x]')

                    # Write decision record
                    dec_id = get_next_decision_id(decisions_dir)
                    dec_path = decisions_dir / f'{dec_id}.md'

                    dec_lines = [
                        f'# {dec_id} -- {rel_path}',
                        '',
                        '**Result:** Auto-resolved',
                        f'**Processed:** {now_str()}',
                        '**Resolved by:** Script (resolve_package_conflicts.py)',
                        '',
                        '| Package | Ours (HEAD) | Theirs (MERGE_HEAD) | Resolution |',
                        '|---------|-------------|----------------------|------------|',
                    ]
                    for d in file_decisions:
                        dec_lines.append(f"| {d['package']} | {d['ours']} | {d['theirs']} | {d['resolution']} |")

                    dec_path.write_text('\n'.join(dec_lines) + '\n', encoding='utf-8')
                    print(f'  [x] Resolved. Decision: {dec_id}')
                except Exception as e:
                    print(f'\n  UNEXPECTED ERROR on \'{rel_path}\': {e}', file=sys.stderr)
                    print(f'\n  To restore this file to its conflicted state, run:', file=sys.stderr)
                    print(f'    git -C "{repo}" checkout -m -- "{rel_path}"', file=sys.stderr)
                    print(f'\n  Batch stopped. Resume from --batch-start {args.batch_start + processed}', file=sys.stderr)
                    sys.exit(1)

        processed += 1
        print()

    print(f'Batch complete. Processed {processed} file(s).')

    if not args.dry_run:
        print()
        print('==========================================')
        print('WARNING: Do not manually edit any file already marked [x] in the phase file.')
        print('If a resolved file needs correction, restore it first:')
        print(f'  git -C "{repo}" checkout -m -- <relative-path>')
        print('Then re-run the script from that file using --batch-start.')
        print('==========================================')


if __name__ == '__main__':
    main()
