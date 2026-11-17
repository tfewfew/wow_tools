"""Export PRR skill requirements and named trainers from pinned public datasets."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile


PROFESSIONDB_SHA256 = 'fa3add2bf667b1499cdac7f9c0abe323571620536ec72ee26c6dec26d3ae98d6'
FOREVER_COMMIT = '6ff5612b54191f297eb77ca8eda81de029d9d6f0'
PROFESSIONS = ('Alchemy', 'Blacksmithing', 'Cooking', 'Enchanting', 'Engineering',
               'Firstaid', 'Fishing', 'Herbalism', 'Leatherworking', 'Mining', 'Skinning', 'Tailoring')
# These IDs lack names in ProfessionDB. Cross-checked against the bundled QuestieDB 1.1.1 NPC records.
TRAINER_NAMES = {3184: "Miao'zan", 3484: "Kil'hala", 4159: "Me'lynn", 7871: "Se'Jib"}


def lua(value):
    if value is True:
        return 'true'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, dict):
        return '{' + ', '.join(key + '=' + lua(item) for key, item in value.items()) + '}'
    if isinstance(value, list):
        return '{' + ', '.join(map(lua, value)) + '}'
    return str(value)


def write_utf8(path, text):
    path.write_bytes(text.encode('utf8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--professiondb-zip', type=Path, required=True)
    parser.add_argument('--forever-data', type=Path, required=True)
    parser.add_argument('--lua-module-root', type=Path)
    args = parser.parse_args()
    if args.lua_module_root:
        sys.path.insert(0, str(args.lua_module_root))
    from lupa.lua51 import LuaRuntime

    if hashlib.sha256(args.professiondb_zip.read_bytes()).hexdigest() != PROFESSIONDB_SHA256:
        raise ValueError('Expected the original ProfessionDB-v1.10.1 release package')
    commit = subprocess.run(['git', '-C', str(args.forever_data), 'rev-parse', 'HEAD'],
                            check=True, capture_output=True, text=True).stdout.strip()
    if commit != FOREVER_COMMIT:
        raise ValueError('Unexpected Efficient Games dataset revision')
    dirty = subprocess.run(['git', '-C', str(args.forever_data), 'status', '--porcelain'],
                           check=True, capture_output=True, text=True).stdout
    if dirty:
        raise ValueError('Efficient Games source checkout has local changes')

    repo = Path(__file__).resolve().parents[3]
    target = repo / 'addon/forerver/wow_tools/prr'
    runtime = LuaRuntime()
    runtime.execute('''
        ns = {Database = {}}
        WoWTools = {prr = {RegisterSource = function(fn) fn('wow_tools', ns) end}}
        core, borrowed, sources, sourceNames, acquire = {}, {}, {}, {}, {}
        local lib = {}
        function lib:IsGameVersion(version) return version == 'Forever' end
        function lib:LoadCore(profession, rows)
            for id, row in pairs(rows) do
                row.profession = profession
                core[id] = row
            end
        end
        function lib:LoadBorrowed(field, donor, ids)
            borrowed[field] = borrowed[field] or {}
            for _, id in ipairs(ids) do borrowed[field][id] = donor end
        end
        function lib:LoadSources(rows) sources = rows end
        function lib:LoadSourceNames(rows) sourceNames = rows end
        function lib:LoadAcquireMethods(rows) acquire = rows end
        function lib:LoadEnchantsCore() end
        function LibStub() return lib end
    ''')
    for name in ('recipes', 'fixes'):
        runtime.execute((target / 'database' / (name + '.lua')).read_text(encoding='utf8'))
    archive = zipfile.ZipFile(args.professiondb_zip)
    for name in (*PROFESSIONS, 'Sources', 'SourceNames', 'AcquireMethods'):
        runtime.execute(archive.read('ProfessionDB/Data/Forever/_core/' + name + '.lua').decode('utf8'))
    globals_ = runtime.globals()
    recipes, fixes = globals_.ns.Database.Recipes, globals_.ns.Database.Fixes
    details, trainers, trainer_sources, observed_ranks = {}, {}, {}, {}
    for spell_id, recipe in recipes.items():
        detail = {}
        core = globals_.core[spell_id]
        if core and core.profession == recipe.profession and core.requiredSkill:
            detail['skill'] = core.requiredSkill
            if globals_.borrowed.requiredSkill[spell_id]:
                detail['skillReference'] = True
        if globals_.acquire[spell_id] == 1:
            detail['autoTaught'] = True
        source = globals_.sources[spell_id]
        trainer_sources[spell_id] = {}
        if source and source.t:
            for _, npc_id in source.t.items():
                trainer_sources[spell_id][npc_id] = {'npcID': npc_id, 'reference': True}
                name = globals_.sourceNames[npc_id] or TRAINER_NAMES.get(npc_id)
                if not name:
                    raise ValueError('Missing trainer name for NPC ' + str(npc_id))
                trainers[npc_id] = {'name': name}
            if source.tn:
                detail['referenceTrainerTotal'] = source.tn
                detail['referenceTrainerListed'] = len(list(source.t.items()))
        details[spell_id] = detail

    input_hashes = {}
    # Each build is a partial observation. Newer observations replace the same NPC/spell pair.
    observations = {}
    paths = sorted((args.forever_data / 'data/wowf').glob('*/trainers.json'),
                   key=lambda path: tuple(map(int, path.parent.name.split('.'))))
    for path in paths:
        blob = path.read_bytes()
        input_hashes[path.relative_to(args.forever_data).as_posix()] = hashlib.sha256(blob).hexdigest()
        for npc_id, npc in json.loads(blob)['trainers'].items():
            if not npc.get('tradeskill'):
                continue
            npc_id = int(npc_id)
            for spell_id, service in npc.get('services', {}).items():
                spell_id = int(spell_id)
                if recipes[spell_id] is None:
                    continue
                observations[spell_id, npc_id] = service
                trainer_sources[spell_id][npc_id] = {'npcID': npc_id}
                trainer = {'name': npc['name']}
                position = next((pos for pos in npc.get('positions', []) if pos.get('uiMap')), None)
                if position:
                    trainer.update(mapID=position['uiMap'], x=position['mapX'], y=position['mapY'])
                trainers[npc_id] = trainer
    for (spell_id, _), service in observations.items():
        rank = service.get('skillRank', 0)
        if rank > 0:
            observed_ranks[spell_id] = min(rank, observed_ranks.get(spell_id, rank))
    for spell_id, detail in details.items():
        if spell_id in observed_ranks and (not detail.get('skill') or detail.get('skillReference')):
            detail['skill'] = observed_ranks[spell_id]
            detail.pop('skillReference', None)
        if trainer_sources[spell_id]:
            detail['trainers'] = sorted(trainer_sources[spell_id].values(),
                                        key=lambda source: (source.get('reference', False), source['npcID']))
        fix = fixes[spell_id]
        if recipes[spell_id].skill or (fix and fix.skill):
            detail.pop('skill', None)
            detail.pop('skillReference', None)
    details = {id_: detail for id_, detail in details.items() if detail}
    repaired = {'native': 0, 'reference': 0, 'remaining': 0}
    for spell_id, recipe in recipes.items():
        fix = fixes[spell_id]
        if (fix and fix.skill) or recipe.skill:
            continue
        detail = details.get(spell_id, {})
        key = ('reference' if detail.get('skillReference') else 'native') if detail.get('skill') else 'remaining'
        repaired[key] += 1
    lines = [
        'WoWTools.prr.RegisterSource(function(...)',
        '-- Generated by skills/wow-tools/scripts/build_prr_recipe_details.py.',
        '-- LibProfessionDB MIT / Efficient Games CC BY 4.0. See RECIPE-SOURCES.json and LICENSE files.',
        'local _, ns = ...',
        'ns.Database.RecipeDetails = {',
    ]
    for spell_id, detail in sorted(details.items()):
        lines.append('    [' + str(spell_id) + '] = ' + lua(detail) + ',')
    lines.extend(['}', 'ns.Database.Trainers = {'])
    for npc_id, trainer in sorted(trainers.items()):
        lines.append('    [' + str(npc_id) + '] = ' + lua(trainer) + ',')
    lines.extend(['}', 'end)', ''])
    write_utf8(target / 'database/recipe_details.lua', '\n'.join(lines))
    write_utf8(target / 'LICENSE-ProfessionDB.txt', archive.read('ProfessionDB/LICENSE').decode('utf8').rstrip() + '\n')
    write_utf8(target / 'LICENSE-EfficientGames.txt', (args.forever_data / 'LICENSE').read_text(encoding='utf8').rstrip() + '\n')
    provenance = {
        'updatedAt': '2026-11-17',
        'professionDB': {'version': '1.10.1', 'license': 'MIT', 'author': 'Pimptasty',
                         'release': 'https://www.curseforge.com/wow/addons/libprofessiondb/files/9653856',
                         'packageSHA256': PROFESSIONDB_SHA256, 'data': 'Data/Forever/_core'},
        'efficientGames': {'repository': 'https://github.com/JIVESCORP/eg-link-output-wowf',
                           'commit': FOREVER_COMMIT, 'license': 'CC BY 4.0',
                           'attribution': 'Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0.',
                           'inputs': input_hashes},
        'transformation': [
            'Export only spell IDs already present in PRR, and only the Forever data tree.',
            'Keep native library requiredSkill, then observed Forever trainer ranks, then flagged Vanilla reference ranks.',
            'Runtime fills missing skills after PRR fixes. Explicit user fixes and known values take priority.',
            'Merge named historical trainer IDs with observed Forever NPC/spell pairs. Observed pairs clear reference flags.',
            'Historical lists are capped by upstream. Preserve listed and total counts. Coverage is partial.',
        ],
        'npcNameCorrections': {'source': 'QuestieDB 1.1.1 NPC records bundled with Raynna Bestiary',
                               'release': 'https://github.com/Questie/QuestieDB/releases/tag/v1.1.1',
                               'names': TRAINER_NAMES},
        'coverage': {'recipes': len(details), 'trainers': len(trainers),
                     'trainerRecipes': sum(bool(detail.get('trainers')) for detail in details.values()),
                     'missingSkills': repaired},
    }
    write_utf8(target / 'RECIPE-SOURCES.json', json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(provenance['coverage'], ensure_ascii=False))


if __name__ == '__main__':
    main()
