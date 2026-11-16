"""Generate the in-game version/date catalog from each client's maintenance table."""

import argparse
from datetime import date
import json
from pathlib import Path
import re


def read_catalog(table):
    records = {}
    for line in table.read_text(encoding='utf-8-sig').splitlines():
        if not line.startswith('| '):
            continue
        cells = [cell.strip() for cell in line.strip('|').split('|')]
        if cells[0] in ('模块', '---'):
            continue
        if len(cells) != 8 or not all(cells):
            raise ValueError(f'{table}: incomplete plugin row {line}')
        key, name, source, version, baseline, updated, adaptations, evidence = cells
        if not re.fullmatch(r'[a-z][a-z0-9_]*', key) or key in records:
            raise ValueError(f'{table}: invalid or duplicate module {key}')
        if date.fromisoformat(updated).isoformat() != updated:
            raise ValueError(f'{table}: invalid update date {updated}')
        records[key] = {'version': version, 'updatedAt': updated}
    if not records:
        raise ValueError(f'{table}: no plugins recorded')
    return records


def render_catalog(records):
    lines = ['-- Generated from ../THIRD_PARTY.md by third_party_catalog.py.\n',
             'WoWTools.thirdPartyCatalog = {\n']
    for key, metadata in records.items():
        version = json.dumps(metadata['version'], ensure_ascii=False)
        updated = json.dumps(metadata['updatedAt'])
        lines.append(f'    {key} = {{ version = {version}, updatedAt = {updated} }},\n')
    lines.append('}\n')
    return ''.join(lines)


def sync_catalogs(repo, write=False):
    for flavor in ('titan', 'forerver'):
        root = repo / 'addon' / flavor
        records = read_catalog(root / 'THIRD_PARTY.md')
        for key, metadata in records.items():
            bootstrap = root / 'wow_tools' / key / 'Bootstrap.lua'
            source = bootstrap.read_text(encoding='utf-8-sig')
            version = re.search(r'sourceVersion\s*=\s*"([^"]+)"', source)
            if version and version.group(1) != metadata['version']:
                raise ValueError(f'{bootstrap}: version differs from maintenance table')
        expected = render_catalog(records)
        target = root / 'wow_tools' / 'ThirdPartyCatalog.lua'
        if write:
            with target.open('w', encoding='utf-8', newline='\n') as output:
                output.write(expected)
        elif target.read_text(encoding='utf-8-sig') != expected:
            raise ValueError(f'{target}: regenerate with third_party_catalog.py --write')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    arguments = parser.parse_args()
    sync_catalogs(Path(__file__).resolve().parents[3], arguments.write)
    print('PASS: third-party maintenance tables and runtime version/date catalogs.')
