"""Compile sources and initialize client API contracts."""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua-module-root', type=Path)
    parser.add_argument('--dungeons-forever-addons-root', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    if args.lua_module_root:
        sys.path.insert(0, str(args.lua_module_root.resolve()))
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise SystemExit('Lua 5.1 is required. Select an existing lupa.lua51 installation with --lua-module-root.') from error

    python_files = list((repo / 'tools/wowAuto/character-create').glob('*.py')) + [Path(__file__)]
    for path in python_files:
        ast.parse(path.read_text(encoding='utf-8-sig'), filename=str(path))
    print(f'PASS: Python syntax and AST ({len(python_files)} files).')

    compiler = LuaRuntime().eval('''function(source, name)
        local chunk, message = loadstring(source, name)
        assert(chunk, message)
    end''')
    if args.dungeons_forever_addons_root:
        addon_root = args.dungeons_forever_addons_root.resolve()
        patch_root = repo / 'skills/wow-tools/patches/dungeons-forever-2.1.95'
        manifest = json.loads((patch_root / 'manifest.json').read_text(encoding='utf-8'))
        assert hashlib.sha256((patch_root / 'performance.patch').read_bytes()).hexdigest() == manifest['patchSha256']
        for name, version in manifest['versions'].items():
            toc = (addon_root / name / (name + '.toc')).read_text(encoding='utf-8-sig')
            metadata = dict(line[3:].split(':', 1) for line in toc.splitlines() if line.startswith('## ') and ':' in line)
            assert metadata['Version'].strip() == version, f'{name} patch baseline version mismatch'
            assert '16001' in metadata['Interface'].replace(' ', '').split(','), f'{name} Forever interface missing'
            for line in toc.splitlines():
                relative = line.split(' [', 1)[0].strip()
                if relative and not relative.startswith('#'):
                    assert (addon_root / name / relative.replace('\\', '/')).is_file(), f'Missing patch dependency {name}/{relative}'
        explore_toc = (addon_root / 'DungeonsForeverExplore/DungeonsForeverExplore.toc').read_text(encoding='utf-8-sig')
        assert explore_toc.index('Core\\ExploreUI.lua') < explore_toc.index('Core\\ExploreMap.lua'), 'Book snapshot must load before map consumers'
        for entry in manifest['files']:
            path = (addon_root / entry['path']).resolve()
            assert path.is_relative_to(addon_root), f'Invalid patch path {path}'
            source = path.read_bytes()
            assert hashlib.sha256(source).hexdigest() == entry['patchedSha256'], f'Patched hash mismatch {path}'
            compiler(source.decode('utf-8-sig'), '@' + str(path))
        print(f"PASS: DungeonsForever patched Lua syntax, TOC dependencies and Forever interfaces ({len(manifest['files'])} files).")
    lua_count = xml_count = inline_count = 0
    for flavor, interface in [('titan', '38002'), ('forerver', '16001')]:
        addon = repo / 'addon' / flavor / 'wow_tools'
        toc = (addon / 'wow_tools.toc').read_text(encoding='utf-8-sig')
        metadata = dict(line[3:].split(':', 1) for line in toc.splitlines() if line.startswith('## ') and ':' in line)
        assert metadata['Interface'].strip() == interface, f'{flavor} TOC interface mismatch'
        for line in toc.splitlines():
            relative = line.strip()
            if relative and not relative.startswith('#'):
                assert (addon / relative.replace('\\', '/')).is_file(), f'Missing TOC dependency {flavor}/{relative}'
        for path in addon.rglob('*.lua'):
            compiler(path.read_text(encoding='utf-8-sig'), '@' + str(path))
            lua_count += 1
        for path in addon.rglob('*.xml'):
            tree = ET.parse(path)
            xml_count += 1
            for node in tree.iter():
                tag = node.tag.rsplit('}', 1)[-1]
                if tag in ('Script', 'Include') and node.get('file'):
                    child = path.parent / node.get('file').replace('\\', '/')
                    assert child.is_file(), f'Missing XML dependency {child}'
                if tag == 'Scripts':
                    for handler in node:
                        body = ''.join(handler.itertext()).strip()
                        if body:
                            compiler('return function(self, ...)\n' + body + '\nend', '@' + str(path))
                            inline_count += 1
        for fixture in ['TitanCompatibility.Tests.lua' if flavor == 'titan' else 'ForeverCompatibility.Tests.lua',
                        'LsToastsLibraries.Tests.lua']:
            runtime = LuaRuntime()
            runtime.globals().TEST_ROOT = repo.as_posix()
            runtime.globals().TEST_FLAVOR = flavor
            path = repo / 'addon/tests' / fixture
            runtime.execute(path.read_text(encoding='utf-8-sig'), name='@' + str(path))
        runtime = LuaRuntime()
        runtime.globals().TEST_ROOT = repo.as_posix()
        runtime.globals().TEST_FLAVOR = flavor
        runtime.globals().TEST_THIRD_PARTY_DISABLED = True
        path = repo / 'addon/tests/ForeverCompatibility.Tests.lua'
        runtime.execute(path.read_text(encoding='utf-8-sig'), name='@' + str(path))
    for path in (repo / 'addon/tests').glob('*.lua'):
        compiler(path.read_text(encoding='utf-8-sig'), '@' + str(path))
        lua_count += 1
    print(f'PASS: Lua 5.1 compilation ({lua_count} files), XML/dependencies ({xml_count} files), inline Lua ({inline_count} handlers).')


if __name__ == '__main__':
    main()
