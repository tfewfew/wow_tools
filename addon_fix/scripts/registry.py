"""Inspect installed addons against the server-specific patch registry."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
INTERFACES = {'titan': '38002', 'forerver': '16001'}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contained(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes its root: {relative}')
    return path


def read_toc(addon, interface):
    candidates = sorted(addon.glob('*.toc'), key=lambda path: (path.stem != addon.name, path.name))
    for path in candidates:
        source = path.read_text(encoding='utf-8-sig')
        metadata = dict(line[3:].split(':', 1) for line in source.splitlines() if line.startswith('## ') and ':' in line)
        interfaces = metadata.get('Interface', '').replace(' ', '').split(',')
        if interface in interfaces:
            return {'version': metadata.get('Version', '').strip(), 'toc': path.name, 'source': source}
    return None


def version_parts(version):
    if not re.fullmatch(r'\d+(?:\.\d+)*', version):
        return None
    parts = tuple(int(part) for part in version.split('.'))
    return parts + (0,) * (8 - len(parts))


def at_or_after(version, threshold):
    if version == threshold:
        return True
    current, first = version_parts(version), version_parts(threshold)
    return current is not None and first is not None and current >= first


def evidence_matches(addons_root, record):
    for entry in record['files']:
        path = contained(addons_root, entry['path'])
        actual = sha256(path) if path.is_file() else None
        if actual != entry['sha256']:
            return False
    return True


def load_mapping(flavor):
    server = ROOT / flavor
    mapping = json.loads((server / 'mapping.json').read_text(encoding='utf-8-sig'))
    if mapping['schemaVersion'] != 1 or mapping['client'] != flavor:
        raise ValueError(f'Invalid registry identity for {flavor}')
    for plugin, patches in mapping['plugins'].items():
        if not plugin or '/' in plugin or '\\' in plugin or plugin in ('.', '..'):
            raise ValueError(f'Invalid addon name {plugin}')
        identifiers = [patch['id'] for patch in patches]
        if len(set(identifiers)) != len(identifiers):
            raise ValueError(f'Duplicate patch identifiers for {plugin}')
        for patch in patches:
            if patch['skipFromVersion'] and not patch['fixedEvidence']:
                raise ValueError(f'Missing fixed-version evidence for {plugin}/{patch["id"]}')
            for evidence in patch['fixedEvidence']:
                if not evidence['version'] or not evidence['reason'].strip() or not evidence['files']:
                    raise ValueError(f'Incomplete fix evidence for {plugin}/{patch["id"]}')
                for entry in evidence['files']:
                    contained(server / plugin, entry['path'].removeprefix(plugin + '/'))
                    if not entry['path'].startswith(plugin + '/') or (entry['sha256'] is not None and not re.fullmatch(r'[0-9a-f]{64}', entry['sha256'])):
                        raise ValueError(f'Invalid fix evidence for {plugin}/{patch["id"]}')
            for relative in patch['variants']:
                manifest_path = contained(server / plugin, relative)
                manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
                if manifest['schemaVersion'] != 1 or manifest['plugin'] != plugin or manifest['id'] != patch['id']:
                    raise ValueError(f'Manifest identity mismatch in {manifest_path}')
                patch_path = contained(manifest_path.parent, manifest['patch'])
                if sha256(patch_path) != manifest['patchSha256']:
                    raise ValueError(f'Patch hash mismatch in {patch_path}')
                paths = [entry['path'] for entry in manifest['files']]
                if len(paths) != len(set(paths)):
                    raise ValueError(f'Duplicate file paths in {manifest_path}')
                for entry in manifest['files']:
                    if not entry['path'].startswith(plugin + '/') or '..' in Path(entry['path']).parts:
                        raise ValueError(f'Wrong addon target in {manifest_path}: {entry["path"]}')
                    for key in ('originalSha256', 'patchedSha256'):
                        if not re.fullmatch(r'[0-9a-f]{64}', entry[key]):
                            raise ValueError(f'Invalid {key} in {manifest_path}')
            for requirement in patch.get('requires', []):
                candidates = mapping['plugins'].get(requirement['plugin'], [])
                if not any(item['id'] == requirement['patch'] for item in candidates):
                    raise ValueError(f'Unknown patch requirement for {plugin}/{patch["id"]}')
    return mapping


def inspect(flavor, addons_root):
    mapping = load_mapping(flavor)
    inventory = {}
    if addons_root.is_dir():
        for addon in sorted(addons_root.iterdir()):
            if addon.is_dir():
                toc = read_toc(addon, INTERFACES[flavor])
                inventory[addon.name] = {key: toc[key] for key in ('version', 'toc')} if toc else {'version': None, 'toc': None}
    results = []
    for plugin, patches in mapping['plugins'].items():
        installed = inventory.get(plugin)
        for patch in patches:
            result = {'plugin': plugin, 'patch': patch['id'], 'description': patch['description'],
                      'version': installed and installed['version'], 'requires': patch.get('requires', [])}
            results.append(result)
            if installed is None:
                result.update(status='absent')
                continue
            if not installed['version']:
                result.update(status='review', reason='Missing compatible TOC or addon version.')
                continue
            threshold = patch['skipFromVersion']
            if threshold and installed['version'] != threshold and (version_parts(installed['version']) is None or version_parts(threshold) is None):
                result.update(status='review', reason='Version range uses a non-numeric version. Review applicability explicitly.')
                continue
            if threshold and at_or_after(installed['version'], threshold):
                evidence = patch['fixedEvidence']
                verified = any(evidence_matches(addons_root, record) for record in evidence)
                result.update(status='retired' if verified else 'review', skipFromVersion=threshold,
                              reason='Recorded fix evidence matches.' if verified else 'Source changed since the recorded fix. Review the current implementation.')
                continue
            variants = []
            for relative in patch['variants']:
                manifest_path = contained(ROOT / flavor / plugin, relative)
                manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
                pending = []
                unknown = []
                for entry in manifest['files']:
                    path = contained(addons_root, entry['path'])
                    actual = sha256(path) if path.is_file() else None
                    if actual == entry['originalSha256']:
                        pending.append(entry)
                    elif actual != entry['patchedSha256']:
                        unknown.append(entry['path'])
                variants.append((manifest_path, manifest, pending, unknown))
            variants.sort(key=lambda variant: variant[1]['version'] != installed['version'])
            compatible = next((variant for variant in variants if not variant[3]), None)
            if compatible:
                manifest_path, manifest, pending, _ = compatible
                result.update(status='applicable' if pending else 'applied', manifest=str(manifest_path),
                              baselineVersion=manifest['version'], pendingFiles=pending)
            else:
                result.update(status='review', reason='Source differs from maintained baselines. Check whether the problem is already fixed before rebasing.',
                              variants=[{'manifest': str(path), 'unknownFiles': unknown} for path, _, _, unknown in variants])
    indexed = {(item['plugin'], item['patch']): item for item in results}
    for _ in results:
        for result in results:
            if result['status'] != 'applicable':
                continue
            for requirement in result['requires']:
                dependency = indexed[(requirement['plugin'], requirement['patch'])]
                if dependency['status'] not in ('applied', 'applicable', 'retired'):
                    result.update(status='review', reason=f'Required repair {dependency["plugin"]}/{dependency["patch"]} needs resolution first.')
                    break
    return {'client': flavor, 'addonsRoot': str(addons_root), 'installed': inventory, 'patches': results}


def record_fixed(flavor, addons_root, review_file):
    import msvcrt

    repo = ROOT.parent
    lock_name = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--git-path', f'addon-fix-{flavor}.lock'], text=True).strip()
    lock_path = (repo / lock_name).resolve()
    with lock_path.open('a+b') as lock:
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as error:
            raise ValueError('Another source review is updating this server mapping. Retry after it finishes.') from error
        try:
            return write_fixed_review(flavor, addons_root, review_file)
        finally:
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)


def write_fixed_review(flavor, addons_root, review_file):
    repo = ROOT.parent
    branch = subprocess.check_output(['git', '-C', str(repo), 'branch', '--show-current'], text=True).strip()
    if branch == 'main':
        raise ValueError('Record source review in the task clone branch before merging.')
    review = json.loads(review_file.read_text(encoding='utf-8-sig'))
    mapping = load_mapping(flavor)
    patch = next(item for item in mapping['plugins'][review['plugin']] if item['id'] == review['patch'])
    toc = read_toc(addons_root / review['plugin'], INTERFACES[flavor])
    if not toc or toc['version'] != review['version']:
        raise ValueError('The reviewed version differs from the installed version.')
    if not review['reason'].strip() or not review['files']:
        raise ValueError('Record the source-level reason and reviewed files.')
    affected = set()
    for relative in patch['variants']:
        manifest = json.loads(contained(ROOT / flavor / review['plugin'], relative).read_text(encoding='utf-8-sig'))
        affected.update(item['path'] for item in manifest['files'])
    if not affected.issubset(review['files']):
        raise ValueError('Review all affected source files before retiring this patch. Include removed paths as evidence.')
    current = next(item for item in inspect(flavor, addons_root)['patches'] if item['plugin'] == review['plugin'] and item['patch'] == review['patch'])
    if current.get('manifest'):
        raise ValueError('This installation matches our own patch or its original baseline. It does not establish an independently fixed version.')
    files = []
    for relative in review['files']:
        if not relative.startswith(review['plugin'] + '/'):
            raise ValueError('Fix evidence must belong to the reviewed addon.')
        path = contained(addons_root, relative)
        files.append({'path': relative, 'sha256': sha256(path) if path.is_file() else None})
    record = {'version': review['version'], 'reason': review['reason'], 'files': files,
              'checkedAt': datetime.now(timezone.utc).isoformat(timespec='seconds')}
    threshold = patch['skipFromVersion']
    if threshold is None or at_or_after(threshold, review['version']):
        patch['skipFromVersion'] = review['version']
    patch['fixedEvidence'] = [item for item in patch['fixedEvidence'] if item['version'] != review['version']] + [record]
    mapping_path = ROOT / flavor / 'mapping.json'
    replacement = mapping_path.with_suffix('.json.tmp')
    replacement.write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    replacement.replace(mapping_path)
    return {'recorded': f'{review["plugin"]}/{review["patch"]}', 'skipFromVersion': patch['skipFromVersion']}


def validate_installed(flavor, addons_root, compiler):
    report = inspect(flavor, addons_root)
    count = 0
    for result in report['patches']:
        if result['status'] == 'absent':
            continue
        if result['status'] not in ('applied', 'retired'):
            raise ValueError(f'Unresolved {result["plugin"]}/{result["patch"]}: {result["status"]}')
        if result['status'] == 'retired':
            continue
        manifest = json.loads(Path(result['manifest']).read_text(encoding='utf-8-sig'))
        toc = read_toc(addons_root / result['plugin'], INTERFACES[flavor])['source']
        for line in toc.splitlines():
            relative = line.split(' [', 1)[0].strip()
            if relative and not relative.startswith('#'):
                if not contained(addons_root / result['plugin'], relative.replace('\\', '/')).is_file():
                    raise ValueError(f'Missing TOC dependency {result["plugin"]}/{relative}')
        positions = [toc.index(relative.replace('/', '\\')) for relative in manifest.get('loadOrder', [])]
        if positions != sorted(positions):
            raise ValueError(f'Invalid patch load order for {result["plugin"]}')
        for entry in manifest['files']:
            path = contained(addons_root, entry['path'])
            compiler(path.read_text(encoding='utf-8-sig'), '@' + str(path))
            count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inspect', 'record-fixed', 'validate'])
    parser.add_argument('--flavor', choices=INTERFACES, required=True)
    parser.add_argument('--addons-root', type=Path)
    parser.add_argument('--review-file', type=Path)
    args = parser.parse_args()
    if args.command == 'validate':
        mapping = load_mapping(args.flavor)
        result = {'client': args.flavor, 'plugins': len(mapping['plugins'])}
    else:
        if args.addons_root is None:
            parser.error('--addons-root is required for installed-addon operations')
        if args.command == 'record-fixed':
            if args.review_file is None:
                parser.error('--review-file is required')
            result = record_fixed(args.flavor, args.addons_root.resolve(), args.review_file)
        else:
            result = inspect(args.flavor, args.addons_root.resolve())
    print(json.dumps(result, ensure_ascii=True, indent=2))


if __name__ == '__main__':
    main()
