"""Build Raynna's offline Forever recipe vendor supplement from pinned inputs."""

import argparse
from collections import defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import sys


BUILD = '1.60.1.71037'
ITEM_SHA256 = '4dc3125995aeda05fe20b4c4b97def50e8444fd2e47bdbfeab97e5ee09533bb7'
EFFICIENT_COMMIT = '423d6c9645cd102406782e7400805a7c738e2d69'
VENDOR_FILES = {
    BUILD: 'fa17ca4f08e059da99e6e2d79a794019463eff07ef25d3ce7ce35d98c42cd3ae',
    '1.60.1.70959': 'fd8045bbfcea4857748721d4fd752e1298b657c707606ac7d11d4c595ae8e7c3',
    '1.60.1.70862': '7d87dd1b6bfef2236883d07e49fe21f4b1a9437d71aae4a85d470c3196537095',
}
# QuestieDB 1.1.5 Forever baked X-Item-277716-14, see REFERENCE-SOURCES.txt.
QUESTIE_ADDITIONS = {277716: {3168}}
PROF_FILES = {
    'Data_ProfSources.lua': '5d71327ecc4213825f1afb8e7013019b2b29a62be750a406e07d975361f584fe',
    'Data_ProfFormulaOffers.lua': 'cec6a04c1764ab091e85b4a8d9dcf56bcb6f2de7ad96865bc1e882c400c3b62b',
    'Data_ProfLearningSources.lua': 'f6797f5027afee44f85e53c1857059065334dd2adf89546d7e80ff9e40286c42',
}
PROFESSIONS = (
    'alchemy', 'blacksmithing', 'cooking', 'enchanting', 'engineering', 'first-aid',
    'fishing', 'herbalism', 'inscription', 'jewelcrafting', 'leatherworking', 'mining',
    'skinning', 'tailoring',
)
OUTPUT = Path(__file__).resolve().parents[3] / 'addon/forerver/wow_tools/raynna_bestiary/RecipeVendors.lua'
ITEM_OFFER = re.compile(r'item:(\d+)(?:#\d+)?')


def read_pinned(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f'{path} does not match the pinned input SHA256')
    return data.decode('utf-8-sig')


def dungeon_vendor_areas(prof_data, recipe_ids):
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime()
    lua.execute('DF_NS = { IsForever = true }')
    for filename, fingerprint in PROF_FILES.items():
        lua.execute(read_pinned(prof_data / filename, fingerprint), name=filename)
    addon = lua.globals().DF_NS
    if addon.ProfSourcesMeta.schemaVersion != 1 or addon.ProfFormulaOffersMeta.schemaVersion != 1:
        raise ValueError('Unsupported DungeonsForeverProf vendor layout')

    areas = defaultdict(dict)

    def add(item_id, npc_id, area_id):
        if item_id in recipe_ids and isinstance(npc_id, int) and npc_id > 0:
            if not areas[item_id].get(npc_id):
                areas[item_id][npc_id] = area_id or 0

    # Individual merchant records carry the more specific location.
    for item_id, source in addon.EnsureProfSources().items():
        for offer in (source.v or {}).values():
            add(item_id, offer.id, offer.area)

    for item_id, offers in addon.EnsureProfFormulaOffers().items():
        if len(offers) % 8:
            raise ValueError(f'Invalid formula offer width for item {item_id}')
        for start in range(1, len(offers) + 1, 8):
            add(item_id, offers[start], offers[start + 4])

    # The learning table also has explicit offers for some profession blueprints.
    learning_merchants = lua.eval('''function(profession)
        local rows = {}
        for _, recipe in DF_NS.ProfLearningSources.Each(profession) do
            for _, route in ipairs(recipe.routes) do
                if route.kind == "item" and route.status == "confirmed" and route.acquisition then
                    for _, offer in ipairs(route.acquisition.vendors) do
                        rows[#rows + 1] = {route.teachingItemID, offer.id, offer.area}
                    end
                end
            end
        end
        return rows
    end''')
    for profession in PROFESSIONS:
        for row in learning_merchants(profession).values():
            add(row[1], row[2], row[3])

    return areas


def observed_merchants(directory, build, recipe_ids):
    data = json.loads(read_pinned(directory / build / 'vendors.json', VENDOR_FILES[build]))
    meta = data['meta']
    if meta['clientBuild'] != build or meta['product'] != 'wowf' or meta['dataset'] != 'vendors':
        raise ValueError(f'Invalid Forever vendor observations for {build}')

    observations = defaultdict(set)
    for npc_id, vendor in data['vendors'].items():
        for key, offer in vendor.get('entries', {}).items():
            match = ITEM_OFFER.fullmatch(key)
            if not match:
                continue
            item_id = int(match[1])
            if item_id != offer['itemId']:
                raise ValueError(f'Conflicting item ID for vendor {npc_id}, offer {key}')
            if item_id in recipe_ids:
                observations[item_id].add(int(npc_id))
    return observations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('items', type=Path, help='Wago Item CSV for ' + BUILD)
    parser.add_argument('prof_data', type=Path, help='DungeonsForeverProf 2.0.3 Core/Data directory')
    parser.add_argument('observations', type=Path, help='Pinned Efficient Games data/wowf directory')
    parser.add_argument('--lua-module-root', type=Path)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    if args.lua_module_root:
        sys.path.insert(0, str(args.lua_module_root.resolve()))

    table = csv.DictReader(io.StringIO(read_pinned(args.items, ITEM_SHA256)))
    recipe_ids = {int(row['ID']) for row in table if row['ClassID'] == '9'}
    areas = dungeon_vendor_areas(args.prof_data, recipe_ids)
    observed = observed_merchants(args.observations, BUILD, recipe_ids)
    historical = defaultdict(set)
    for build in VENDOR_FILES:
        if build != BUILD:
            for item_id, npcs in observed_merchants(args.observations, build, recipe_ids).items():
                historical[item_id].update(npcs)
    supplement_ids = areas.keys() | observed.keys() | historical.keys() | QUESTIE_ADDITIONS.keys()
    if not supplement_ids <= recipe_ids:
        raise ValueError('A vendor supplement uses a non-recipe item ID')

    lines = [
        'WoWTools.raynnaBestiary.RegisterSource(function(...)',
        '-- Generated by skills/wow-tools/scripts/build_raynna_recipe_vendors.py.',
        f'-- Forever {BUILD}, DungeonsForeverProf 2.0.3, Efficient Games {EFFICIENT_COMMIT}.',
        '-- Item ID -> NPC ID -> {area ID or 0, source (default DF, 1 EG current, 2 EG earlier, 3 Questie)}.',
        'local _, Addon = ...',
        'Addon.RecipeVendors = {',
    ]
    count = 0
    for item_id in sorted(supplement_ids):
        area_by_npc = areas.get(item_id, {})
        sources = dict.fromkeys(historical.get(item_id, ()), ',2')
        sources.update(dict.fromkeys(area_by_npc, ''))
        sources.update(dict.fromkeys(QUESTIE_ADDITIONS.get(item_id, ()), ',3'))
        sources.update(dict.fromkeys(observed.get(item_id, ()), ',1'))
        entries = [
            f'[{npc_id}]={{{area_by_npc.get(npc_id, 0)}{source}}}'
            for npc_id, source in sorted(sources.items())
        ]
        count += len(entries)
        lines.append(f'    [{item_id}] = {{' + ','.join(entries) + '},')
    lines.extend(('}', 'end)'))
    args.output.write_bytes(('\n'.join(lines) + '\n').encode('utf-8'))
    print(f'{len(recipe_ids)} recipe IDs checked, {len(supplement_ids)} with supplement, {count} vendor links.')


if __name__ == '__main__':
    main()
