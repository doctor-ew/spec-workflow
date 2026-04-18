#!/usr/bin/env python3
"""build_phase_files.py
Generates Phase-N-*.md files from ConflictClassification.md.
Python port of Build-PhaseFiles.ps1. Stdlib only.

Usage:
    python3 build_phase_files.py [--planning-dir PATH]
    python3 build_phase_files.py --help
"""

import argparse
import re
from collections import OrderedDict
from pathlib import Path


STATUS_LEGEND = """\
## Status Legend
| Symbol | Status |
|--------|--------|
| `[ ]`  | Not Started |
| `[>]`  | In Progress |
| `[!]`  | Flagged for Review |
| `[x]`  | Complete |
"""

# Map section header prefix → phase config
# Phase 2 intentionally aggregates multiple classification groups
PHASES = OrderedDict([
    ('UU / Packages',   {'file': 'Phase-1-Packages.md',  'title': 'Phase 1 - UU / Packages',  'desc': 'Package files (csproj, nuspec, packages.config). Resolve by version preference.'}),
    ('UU / CSharp',     {'file': 'Phase-2-Code.md',      'title': 'Phase 2 - UU / Code',       'desc': 'Code conflicts (cs, js, cshtml). Each file requires individual review.'}),
    ('UU / JavaScript', {'file': 'Phase-2-Code.md',      'title': None,                         'desc': None}),
    ('UU / Views',      {'file': 'Phase-2-Code.md',      'title': None,                         'desc': None}),
    ('UU / Pipeline',   {'file': 'Phase-3-Pipelines.md', 'title': 'Phase 3 - UU / Pipeline',   'desc': 'Pipeline yml files. Each file requires individual review.'}),
    ('UU / Config',     {'file': 'Phase-4-Config.md',    'title': 'Phase 4 - UU / Config',     'desc': 'Config files. Each file requires individual review.'}),
    ('UU / Other',      {'file': 'Phase-5-Other.md',     'title': 'Phase 5 - UU / Other',      'desc': 'Unclassified conflict files. Identify and review before resolving.'}),
    ('AA / Both-added', {'file': 'Phase-6-BothAdded.md', 'title': 'Phase 6 - AA / Both-added', 'desc': 'Files added independently on both branches. Do not resolve without discussion.'}),
])


def parse_classification(path: Path) -> dict:
    """Parse ConflictClassification.md into {section_key: [files]}."""
    sections = {}
    current_key = None
    section_pattern = re.compile(r'^## (.+?) - \d+ file')

    for line in path.read_text(encoding='utf-8').splitlines():
        m = section_pattern.match(line)
        if m:
            current_key = m.group(1).strip()
            sections[current_key] = []
        elif current_key and line.startswith('- '):
            sections[current_key].append(line[2:].strip())

    return sections


def main():
    parser = argparse.ArgumentParser(
        description='Build phase files from ConflictClassification.md'
    )
    parser.add_argument('--planning-dir', default='./merge-planning', help='Planning directory (default: ./merge-planning)')
    args = parser.parse_args()

    planning_dir = Path(args.planning_dir).resolve()
    classification_path = planning_dir / 'ConflictClassification.md'

    if not classification_path.exists():
        print(f'ERROR: {classification_path} not found. Run get_conflict_classification.py first.')
        exit(1)

    sections = parse_classification(classification_path)

    # Accumulate files per output file
    file_contents = OrderedDict()

    for section_key, phase in PHASES.items():
        out_file = phase['file']
        files = sections.get(section_key, [])

        if out_file not in file_contents:
            file_contents[out_file] = {'title': phase['title'], 'desc': phase['desc'], 'rows': []}

        file_contents[out_file]['rows'].extend(files)

    # Write phase files
    for out_file, data in file_contents.items():
        sb = []
        if data['title']:
            sb.append(f"# {data['title']}")
            sb.append('')
            sb.append(data['desc'])
            sb.append('')
        sb.append(STATUS_LEGEND)
        sb.append('## Files')
        sb.append('')
        sb.append('| Status | File | Notes |')
        sb.append('|--------|------|-------|')

        for f in sorted(data['rows']):
            sb.append(f'| `[ ]` | {f} | |')

        sb.append('')

        out_path = planning_dir / out_file
        out_path.write_text('\n'.join(sb) + '\n', encoding='utf-8')
        print(f'Written: {out_file} ({len(data["rows"])} files)')

    print('Done.')


if __name__ == '__main__':
    main()
