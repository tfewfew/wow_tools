"""Export PRR skill requirements and named trainers from pinned public datasets."""

import argparse
import csv
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile


PROFESSIONDB_SHA256 = 'fa3add2bf667b1499cdac7f9c0abe323571620536ec72ee26c6dec26d3ae98d6'
FOREVER_COMMIT = '06b4cc7b814c1cb16ff56b746181c2c62944fbc9'
AUDIT_BASELINE_COMMIT = '6ff5612b54191f297eb77ca8eda81de029d9d6f0'
PRR_AUDIT_BASELINE = 'b2cc8f214ddd55f9e7b7c3071aa4f03136f6c4f9'  # Imported 1.5.2 recipe data
CLIENT_BUILD = '1.60.1.70938'
SKILLLINE_SHA256 = '6696abd03ef90ad250a12ac23778616c292c46f6a0082130fbe187c96ead0aa0'
ITEMSPARSE_SHA256 = 'fdc65396e8a1103ea5f552ea59aaebc0e73ba572612a3412c50e636b54c90b41'
TEACHING_TABLES = {
    'ItemEffect': '02b66eca6ae40a0ec67f972999456ce1d950e316c6f1f078b03f3d267d8ce420',
    'ItemXItemEffect': '4a0604e047f72390991e3a7914fe3e309829fb8773c36f5e4aff5628b7913f88',
    'SpellEffect': 'f419db3f95ef93b2cf052d9c3996ec355df60846f1fa24c671822aacfa8f59a3',
}
PROFESSIONS = ('Alchemy', 'Blacksmithing', 'Cooking', 'Enchanting', 'Engineering',
               'Firstaid', 'Fishing', 'Herbalism', 'Leatherworking', 'Mining', 'Skinning', 'Tailoring')
# These IDs lack names in ProfessionDB. Cross-checked against the bundled QuestieDB 1.1.1 NPC records.
TRAINER_NAMES = {3184: "Miao'zan", 3484: "Kil'hala", 4159: "Me'lynn", 7871: "Se'Jib"}
CALIBRATION_BUILD = '1.60.1.71037'
CALIBRATION_TABLES = {
    'SkillLineAbility': SKILLLINE_SHA256,
    'ItemSparse': '40a846d609a35d6fa4df63dfe0fed4166a96e753d2fe8f7f87fb0023ab50a1b0',
    'ItemEffect': '0272d47d6bed698febbe29a4b58882adcf6c2bf43d211f926bfd96be47ae8a23',
    'ItemXItemEffect': 'dd612cf4d32a4287861f57b9a19421f6bf111531b084197a3033a4f8c794c397',
    'SpellEffect': 'a0afcd6a6bfd078e6eaf77df82922c435a9a4558593cf78dfb483631a7b9bfd3',
}
CALIBRATION_TRAINER_COMMIT = '5d76a9e5bbba33b97a98774103ccc607ad2463c1'
CALIBRATION_TRAINERS = {
    '1.60.1.70938': '4d94357ea0fde25af338781e72c372489a6a0c5cf7a3c316b344953ced6420ad',
    '1.60.1.70959': 'ee9d2ae0b58b332ae0508421ad2816ae9bdcbbc623f1fdbea1cca559ec1cf154',
    '1.60.1.71037': 'c78ea2bbaef22059f8bd4c8d542b246ce9126e3ba0f65395da7c320286f18f03',
}
TRAINER_SKILL_NAMES = {
    129: {'First Aid'}, 164: {'Blacksmithing'}, 165: {'Leatherworking'},
    171: {'Alchemy', '연금술'}, 182: {'Herbalism', '약초채집'}, 185: {'Cooking'},
    186: {'Mining'}, 197: {'Tailoring'}, 202: {'Engineering'},
    333: {'Enchanting'}, 356: {'Fishing'}, 393: {'Skinning'},
}
HOTFIX_URL = 'https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-10-2026'


def lua(value):
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, dict):
        return '{' + ', '.join(key + '=' + lua(item) for key, item in value.items()) + '}'
    if isinstance(value, list):
        return '{' + ', '.join(map(lua, value)) + '}'
    return str(value)


def write_utf8(path, text):
    if not path.exists() or path.read_text(encoding='utf8') != text:
        path.write_bytes(text.encode('utf8'))


def read_client_table(path, expected_hash):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
        raise ValueError('Unexpected client table fingerprint: ' + str(path))
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def teaching_item_index(tables):
    taught_spells = defaultdict(set)
    for row in tables['SpellEffect']:
        if int(row['Effect']) == 36:
            taught_spells[int(row['SpellID'])].add(int(row['EffectTriggerSpell']))
    effects = {int(row['ID']): row for row in tables['ItemEffect']}
    teaching_items = defaultdict(set)
    for row in tables['ItemXItemEffect']:
        effect = effects.get(int(row['ItemEffectID']))
        if not effect:
            continue
        spell_id = int(effect['SpellID'])
        spells = taught_spells[spell_id].copy()
        if int(effect['TriggerType']) == 6:
            spells.add(spell_id)
        for taught in spells:
            teaching_items[taught].add(int(row['ItemID']))
    return teaching_items


def calibration_observations(args, recipes):
    observations = {}
    for build, digest in CALIBRATION_TRAINERS.items():
        path = f'data/wowf/{build}/trainers.json'
        blob = subprocess.check_output(['git', '-C', str(args.forever_data), 'show',
                                        f'{CALIBRATION_TRAINER_COMMIT}:{path}'])
        if hashlib.sha256(blob).hexdigest() != digest:
            raise ValueError('Unexpected trainer dataset fingerprint: ' + path)
        snapshot = json.loads(blob)
        if (snapshot['meta']['product'], snapshot['meta']['clientBuild']) != ('wowf', build):
            raise ValueError('Unexpected trainer dataset identity: ' + path)
        by_spell = defaultdict(list)
        for npc_id, npc in snapshot['trainers'].items():
            if not npc.get('tradeskill'):
                continue
            for key, service in npc.get('services', {}).items():
                spell_id = int(key)
                recipe = recipes[spell_id]
                if (recipe and service.get('spellId') == spell_id and not service.get('step')
                        and service.get('skillRank', 0) > 0
                        and service.get('skill') in TRAINER_SKILL_NAMES.get(recipe.profession, set())):
                    by_spell[spell_id].append((service['skillRank'], int(npc_id)))
        for spell_id, ranks in by_spell.items():
            rank = min(rank for rank, _ in ranks)
            observations[spell_id] = {'type': 'trainer', 'rank': rank, 'build': build,
                                      'npcIDs': sorted(npc for value, npc in ranks if value == rank)}
    return observations


def calibrate_skills(args, recipes, fixes, details, verification, core, borrowed):
    tables = {name: read_client_table(args.calibration_tables / f'{name}-{CALIBRATION_BUILD}.csv', digest)
              for name, digest in CALIBRATION_TABLES.items()}
    trainer = calibration_observations(args, recipes)
    teaching_items = teaching_item_index(tables)
    items = {int(row['ID']): row for row in tables['ItemSparse']}
    ranges = defaultdict(list)
    for row in tables['SkillLineAbility']:
        ranges[int(row['Spell']), int(row['SkillLine'])].append(row)

    changes, audit = {}, []
    equal = {'corrected': [], 'verified': [], 'retained': []}
    historical = {row['spellID'] for row in verification['unknownSkills'] if row['status'] == 'verified'}
    unknown = 0
    for spell_id, recipe in sorted(recipes.items()):
        fix, detail = fixes[spell_id], details.get(spell_id, {})
        previous = (fix.skill if fix else None) or (detail.get('skill') if detail.get('skillCorrection')
                                                   else recipe.skill or detail.get('skill'))
        if fix and fix.skillUnknown:
            previous = None
        native = ranges[spell_id, recipe.profession]
        values = {(int(row['TrivialSkillLineRankLow']), int(row['TrivialSkillLineRankHigh'])) for row in native}
        if len(values) != 1:
            raise ValueError(f'Missing or ambiguous client thresholds for spell {spell_id}')
        raw_yellow, raw_gray = next(iter(values))
        yellow, gray = raw_yellow, raw_gray
        if spell_id == 1263031:
            # Blizzard reduced the original 145 cap by 15. The build table stores 125 in both fields.
            if (yellow, raw_gray, recipe.gray) != (125, 125, 145):
                raise ValueError('Recheck the Tanning Rack server hotfix')
            gray = 130
        if not 0 <= yellow <= gray:
            yellow, gray = 0, 0

        candidates = []
        for item_id in sorted(teaching_items[spell_id]):
            item = items.get(item_id)
            if item and int(item['RequiredSkill']) == recipe.profession and int(item['RequiredSkillRank']) > 0:
                candidates.append({'type': 'item', 'rank': int(item['RequiredSkillRank']), 'itemID': item_id})
        if spell_id in trainer:
            candidates.append(trainer[spell_id])
        for row in native:
            if int(row['AcquireMethod']) in (1, 2):
                candidates.append({'type': 'automatic', 'rank': max(1, int(row['MinSkillLineRank'])),
                                   'skillLineAbilityID': int(row['ID'])})
                break
        chosen = min(candidates, key=lambda source: source['rank'], default=None)
        skill = previous
        if chosen and not (fix and fix.skillUnknown):
            skill = chosen['rank']

        updated = {}
        if previous != skill:
            updated['skill'] = skill
        if (recipe.yellow or 0, recipe.gray or 0) != (yellow, gray):
            updated.update(yellow=yellow, gray=gray)
        if spell_id == 9957 and chosen and chosen.get('itemID') == 7994:
            updated.update(recipeItem=7994, recipeItemBound=int(items[7994]['Bonding']) == 1)
        if updated:
            changes[spell_id] = updated
            entry = {'spellID': spell_id, 'profession': recipe.profession,
                     'previous': {'skill': previous, 'yellow': recipe.yellow, 'gray': recipe.gray},
                     'corrected': updated, 'sources': candidates}
            if 'yellow' in updated:
                entry['clientThresholds'] = {'yellow': raw_yellow, 'gray': raw_gray,
                                             'skillLineAbilityIDs': sorted(int(row['ID']) for row in native)}
                if spell_id == 1263031:
                    entry['serverHotfix'] = {'url': HOTFIX_URL, 'date': '2026-11-06',
                                             'gray': gray, 'previousGray': recipe.gray, 'delta': -15}
                elif raw_yellow > raw_gray:
                    entry['thresholdStatus'] = 'unknownInvertedClientRange'
            audit.append(entry)

        if previous is not None and previous == recipe.yellow:
            lib = core[spell_id]
            corroborated = (spell_id in historical or (lib and lib.profession == recipe.profession
                            and lib.requiredSkill == previous and not borrowed[spell_id]))
            outcome = 'corrected' if updated else 'verified' if chosen or corroborated else 'retained'
            equal[outcome].append(spell_id)
        if skill is None:
            unknown += 1

    return changes, {
        'build': CALIBRATION_BUILD,
        'clientTables': {name: {'url': f'https://wago.tools/db2/{name}/csv?build={CALIBRATION_BUILD}', 'sha256': digest}
                         for name, digest in CALIBRATION_TABLES.items()},
        'trainerObservations': {'commit': CALIBRATION_TRAINER_COMMIT,
                                'inputs': {f'data/wowf/{build}/trainers.json': digest
                                           for build, digest in CALIBRATION_TRAINERS.items()}},
        'policy': ['Read thresholds from the matching current SkillLineAbility spell and profession.',
                   'Suppress an inverted client range and apply the independently documented Tanning Rack hotfix.',
                   'Use the earliest verified learning route across teaching items, automatic grants and the newest trainer observation.',
                   'A trainer can require a different rank from an available item or automatic grant.',
                   'A matching prior rank without additional evidence is listed as retained, and unknown ranks stay unknown.'],
        'recipesChecked': len(list(recipes.items())),
        'unknownLearningRanks': unknown,
        'learningRanksChanged': sum('skill' in row for row in changes.values()),
        'thresholdsChanged': sum('yellow' in row for row in changes.values()),
        'previousLearnEqualsYellow': equal,
        'changes': audit,
    }


def verify_learning(repo, args, recipes, details, trainers, client_ranges, client_items):
    evidence_path = repo / 'skills/wow-tools/data/prr-learning-evidence.json'
    evidence_text = evidence_path.read_text(encoding='utf8')
    evidence = json.loads(evidence_text)
    targets = evidence['targets']
    tables = {name: read_client_table(args.item_sparse_csv.parent / (name + '-' + CLIENT_BUILD + '.csv'), digest)
              for name, digest in TEACHING_TABLES.items()}
    teaching_items = teaching_item_index(tables)

    documented = {}
    documentation = {row['spellID']: row for row in evidence['foreverDB']['recipes']}
    for row in evidence['foreverDB']['recipes']:
        recipe = recipes[row['spellID']]
        native = client_ranges.get((row['spellID'], row['profession']))
        if (recipe and native and recipe.profession == row['profession']
                and int(native['ID']) == row['skillLineAbilityID']
                and (recipe.yellow, recipe.gray) == (row['yellow'], row['gray'])
                and row['source'] == 'trainer' and row['trainingCost'] is not None
                and row['trainerNPCIDs']):
            documented[row['spellID']] = row

    beta, beta_inputs = {}, {}
    for path in sorted((args.forever_data / 'data/wow_classic_beta').glob('*/trainers.json'),
                       key=lambda path: tuple(map(int, path.parent.name.split('.')))):
        relative = path.relative_to(args.forever_data).as_posix()
        beta_inputs[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        for npc_id, npc in json.loads(path.read_bytes())['trainers'].items():
            if npc.get('tradeskill'):
                for spell_id, service in npc.get('services', {}).items():
                    beta[int(spell_id), int(npc_id)] = (service, npc, relative)

    skill_audit = []
    local_captures = {row['spellID']: row for row in evidence['localTrainerCaptures']['records']}
    question_review = evidence['questionMarkReview']
    reviewed = {row['spellID']: row for row in question_review['records']}
    if (set(reviewed) != set(question_review['targetSpellIDs'])
            or len(reviewed) != len(question_review['records'])
            or question_review['clientBuild'] != CLIENT_BUILD):
        raise ValueError('Incomplete question-mark recipe review')
    for spell_id, review in reviewed.items():
        recipe = recipes[spell_id]
        native = client_ranges[spell_id, review['profession']]
        if (recipe.profession != review['profession'] or recipe.item != review['itemID']
                or recipe.recipeItem != review['recipeItemID']
                or (recipe.yellow, recipe.gray) != (review['yellow'], review['gray'])
                or int(native['ID']) != review['skillLineAbilityID']):
            raise ValueError('Reviewed recipe identity changed for spell ' + str(spell_id))
        if review['yellow'] is not None and (
                int(native['TrivialSkillLineRankLow']) != review['yellow']
                or int(native['TrivialSkillLineRankHigh']) != review['gray']):
            raise ValueError('Reviewed client thresholds changed for spell ' + str(spell_id))
        if review['status'] not in ('verified', 'unresolved') or (
                ('requirement' in review) != (review['status'] == 'verified')):
            raise ValueError('Invalid learning review disposition for spell ' + str(spell_id))
        if review['status'] == 'verified':
            requirement = review['requirement']
            if (requirement['skill'] <= 0 or not requirement['sourceIDs']
                    or not all(key in question_review['sources'] for key in requirement['sourceIDs'])
                    or not all(str(npc_id) in question_review['trainers'] for npc_id in requirement['trainerNPCIDs'])):
                raise ValueError('Incomplete learning evidence for spell ' + str(spell_id))
            difficulty = requirement.get('documentedDifficulty')
            if difficulty and difficulty != [requirement['skill'], review['yellow'],
                                            (review['yellow'] + review['gray']) // 2, review['gray']]:
                raise ValueError('Documented difficulty mismatch for spell ' + str(spell_id))
    for spell_id in targets['unknownSkills']:
        recipe = recipes[spell_id]
        detail = details.setdefault(spell_id, {})
        native = client_ranges[spell_id, recipe.profession]
        record = {'spellID': spell_id, 'profession': recipe.profession,
                  'skillLineAbilityID': int(native['ID']), 'nativeMinimum': int(native['MinSkillLineRank']),
                  'acquireMethod': int(native['AcquireMethod']), 'teachingItems': [],
                  'status': 'unresolved', 'reason': 'No verified learning requirement in the checked sources'}
        raw_doc = documentation.get(spell_id)
        record['documentationCheck'] = {'status': 'recipeNotListed'}
        if raw_doc:
            record['documentationCheck'] = {
                'page': raw_doc['page'], 'reportedRank': raw_doc['reportedLearnRank'],
                'status': 'explicitTrainerListed' if spell_id in documented else 'inferredOrClientMismatch',
            }
        candidates = teaching_items[spell_id].copy()
        if recipe.recipeItem:
            candidates.add(recipe.recipeItem)
        for item_id in sorted(candidates):
            item = client_items.get(item_id)
            item_record = {'itemID': item_id, 'presentInCurrentItemSparse': bool(item)}
            if item:
                item_record.update(requiredSkill=int(item['RequiredSkill']), requiredRank=int(item['RequiredSkillRank']))
            record['teachingItems'].append(item_record)
        verified, source = None, None
        for item in record['teachingItems']:
            if item.get('requiredSkill') == recipe.profession and item.get('requiredRank', 0) > 0:
                verified = min(verified or item['requiredRank'], item['requiredRank'])
                source = 'Forever ItemSparse teaching item'
        if int(native['AcquireMethod']) in (1, 2):
            verified, source = max(1, int(native['MinSkillLineRank'])), 'Forever automatic skill grant'
        capture = local_captures.get(spell_id)
        if capture and not verified:
            expected_build = ':'.join(CLIENT_BUILD.rsplit('.', 1))
            if (capture['build'] != expected_build or capture['profession'] != recipe.profession
                    or not capture['trainerObserved'] or capture['skill'] <= 0):
                raise ValueError('Invalid local trainer capture for spell ' + str(spell_id))
            verified, source = capture['skill'], 'Local Forever trainer capture'
            record.update(build=capture['build'], trainingCost=capture['trainingCost'])
        review = reviewed.get(spell_id)
        requirement = review.get('requirement') if review else None
        if requirement and not verified:
            verified, source = requirement['skill'], 'Reviewed Forever recipe documentation'
            record.update(documentationSources=[question_review['sources'][key]['url']
                                                for key in requirement['sourceIDs']],
                          trainerNPCIDs=requirement['trainerNPCIDs'], trainingCost=requirement['trainingCost'])
            if requirement.get('trainingCostMeaning'):
                record['trainingCostMeaning'] = requirement['trainingCostMeaning']
        if review and not verified:
            record['reason'] = review['reason']
        doc = documented.get(spell_id)
        if doc and not verified:
            verified, source = doc['reportedLearnRank'], 'ForeverDB explicit trainer listing'
            record.update(documentationPage=doc['page'], trainerNPCIDs=doc['trainerNPCIDs'],
                          trainingCost=doc['trainingCost'])
        for row in evidence['profit']['records']:
            if row['spellID'] == spell_id and row['profession'] == recipe.profession and not verified:
                record['historicalTrainer'] = row
                record['reason'] = 'Only a beta trainer rank is available, current acquisition is unverified'
        if verified:
            detail['skill'] = verified
            detail.pop('skillReference', None)
            if source == 'Forever automatic skill grant':
                detail['autoTaught'] = True
            record.update(status='verified', skill=verified, source=source)
            record.pop('reason')
        skill_audit.append(record)

    trainer_audit = []
    for spell_text, npc_ids in targets['referenceTrainers'].items():
        spell_id = int(spell_text)
        detail = details[spell_id]
        sources = {row['npcID']: row for row in detail['trainers']}
        doc = documented.get(spell_id)
        record = {'spellID': spell_id, 'verifiedDocumentationNPCIDs': [], 'verifiedBetaNPCIDs': [],
                  'rejectedCrossExpansionNPCIDs': [], 'betaObservations': {}}
        raw_doc = documentation.get(spell_id)
        if raw_doc:
            record['documentationPage'] = raw_doc['page']
            record['documentationStatus'] = 'explicitTrainerListed' if doc else 'inferredOrClientMismatch'
        for npc_id in npc_ids:
            source = sources[npc_id]
            status = 'rejectedCrossExpansionNPCIDs'
            if (spell_id, npc_id) in beta:
                _, npc, relative = beta[spell_id, npc_id]
                position = next((pos for pos in npc.get('positions', []) if pos.get('uiMap')), None)
                if position:
                    source.pop('reference', None)
                    trainer = trainers[npc_id]
                    if not trainer.get('mapID'):
                        trainer.update(mapID=position['uiMap'], x=position['mapX'], y=position['mapY'])
                    status = 'verifiedBetaNPCIDs'
                    record['betaObservations'][str(npc_id)] = relative
            if doc and npc_id in doc['trainerNPCIDs']:
                position = evidence['foreverDB']['trainers'][str(npc_id)]
                source.pop('reference', None)
                if not trainers[npc_id].get('mapID'):
                    trainers[npc_id].update({key: position[key] for key in ('mapID', 'x', 'y')})
                status = 'verifiedDocumentationNPCIDs'
                record['documentationPage'] = doc['page']
            requirement = reviewed.get(spell_id, {}).get('requirement', {})
            if npc_id in requirement.get('trainerNPCIDs', []):
                source.pop('reference', None)
                position = question_review['trainers'][str(npc_id)]
                if not trainers[npc_id].get('mapID'):
                    trainers[npc_id].update({key: position[key] for key in ('mapID', 'x', 'y')})
                status = 'verifiedDocumentationNPCIDs'
                record['documentationPage'] = question_review['sources'][requirement['sourceIDs'][0]]['url']
            record[status].append(npc_id)
        if not record['betaObservations']:
            record.pop('betaObservations')
        trainer_audit.append(record)
        detail['trainers'] = sorted(sources.values(), key=lambda row: (row.get('reference', False), row['npcID']))
    # New documented recipes also use the same location-only runtime lookup.
    for record in skill_audit:
        if record.get('source') == 'ForeverDB explicit trainer listing':
            spell_id = record['spellID']
            sources = {row['npcID']: row for row in details[spell_id].get('trainers', [])}
            for npc_id in record['trainerNPCIDs']:
                sources[npc_id] = {'npcID': npc_id}
                position = evidence['foreverDB']['trainers'][str(npc_id)]
                if not trainers.get(npc_id, {}).get('mapID'):
                    trainers[npc_id] = {key: position[key] for key in ('name', 'mapID', 'x', 'y')}
            details[spell_id]['trainers'] = sorted(sources.values(), key=lambda row: (row.get('reference', False), row['npcID']))
    for review in evidence['recipeTrainerReviews']['recipes']:
        spell_id = review['spellID']
        if recipes[spell_id].profession != review['profession']:
            raise ValueError('Reviewed trainer profession mismatch for spell ' + str(spell_id))
        detail = details.setdefault(spell_id, {})
        sources = {row['npcID']: row for row in detail.get('trainers', []) if not row.get('reference')}
        for npc_id in review['trainerNPCIDs']:
            sources[npc_id] = {'npcID': npc_id}
            position = evidence['recipeTrainerReviews']['trainers'][str(npc_id)]
            if not trainers.get(npc_id, {}).get('mapID'):
                trainers[npc_id] = {key: position[key] for key in ('name', 'mapID', 'x', 'y')}
        detail['trainers'] = sorted(sources.values(), key=lambda row: row['npcID'])
    for spell_id, review in reviewed.items():
        requirement = review.get('requirement')
        if not requirement:
            continue
        detail = details.setdefault(spell_id, {})
        if detail.get('skill') != requirement['skill']:
            raise ValueError('Reviewed requirement was not applied for spell ' + str(spell_id))
        teaching_item = requirement.get('teachingItem')
        if teaching_item:
            if (teaching_item['sourceID'] not in requirement['sourceIDs'] or teaching_item['itemID'] <= 0
                    or not isinstance(teaching_item['bound'], bool)
                    or recipes[spell_id].recipeItem not in (None, teaching_item['itemID'])):
                raise ValueError('Reviewed teaching item mismatch for spell ' + str(spell_id))
            detail.update(recipeItem=teaching_item['itemID'], recipeItemBound=teaching_item['bound'])
        sources = {row['npcID']: row for row in detail.get('trainers', []) if not row.get('reference')}
        for npc_id in requirement['trainerNPCIDs']:
            sources[npc_id] = {'npcID': npc_id}
            position = question_review['trainers'][str(npc_id)]
            if not trainers.get(npc_id, {}).get('mapID'):
                trainers[npc_id] = {key: position[key] for key in ('name', 'mapID', 'x', 'y')}
        if sources:
            detail['trainers'] = sorted(sources.values(), key=lambda row: row['npcID'])
    for detail in details.values():
        # Sources.lua imports Wrath/Cataclysm emulator trainer lists. Only corroborated pairs can be shown.
        confirmed = [row for row in detail.get('trainers', []) if not row.get('reference')]
        detail.pop('referenceTrainerTotal', None)
        detail.pop('referenceTrainerListed', None)
        if confirmed:
            detail['trainers'] = confirmed
        else:
            detail.pop('trainers', None)
    return {'baseline': evidence['targetBaseline'], 'evidenceFile': evidence_path.relative_to(repo).as_posix(),
            'evidenceSHA256': hashlib.sha256(evidence_text.encode('utf8')).hexdigest(),
            'evidenceNormalization': 'UTF-8 with LF line endings', 'policy': evidence['policy'],
            'foreverDB': {'pages': evidence['foreverDB']['pages'], 'trainers': evidence['foreverDB']['trainers']},
            'profit': evidence['profit'], 'betaInputs': beta_inputs,
            'localTrainerCaptures': evidence['localTrainerCaptures'],
            'recipeTrainerReviews': evidence['recipeTrainerReviews'],
            'questionMarkReview': question_review,
            'trainerFactions': evidence['trainerFactions'],
            'unknownSkills': skill_audit,
            'referenceTrainers': sorted(trainer_audit, key=lambda row: row['spellID'])}


def remove_absorbed_corrections(details, calibration, recipes, fixes):
    absorbed = {'supplementedSkills': [], 'calibratedSkills': [], 'calibratedThresholds': []}
    for spell_id, detail in sorted(details.items()):
        skill, recipe = detail.get('skill'), recipes[spell_id]
        if skill and not detail.get('skillReference') and recipe and recipe.skill == skill:
            detail.pop('skill')
            detail.pop('skillCorrection', None)
            absorbed['supplementedSkills'].append(spell_id)
    for spell_id, fields in sorted(calibration.items()):
        recipe = recipes[spell_id]
        if not recipe:
            continue
        fix, detail = fixes[spell_id], details.get(spell_id, {})
        skill = fields.get('skill')
        if (skill and recipe.skill == skill and (not fix or not fix.skill or fix.skill == skill)
                and (not detail.get('skill') or detail.get('skillReference') or detail['skill'] == skill)):
            fields.pop('skill')
            absorbed['calibratedSkills'].append(spell_id)
        if 'yellow' in fields and (recipe.yellow or 0, recipe.gray or 0) == (fields['yellow'], fields['gray']):
            fields.pop('yellow')
            fields.pop('gray')
            absorbed['calibratedThresholds'].append(spell_id)
    return absorbed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--professiondb-zip', type=Path, required=True)
    parser.add_argument('--forever-data', type=Path, required=True)
    parser.add_argument('--skillline-ability-csv', type=Path, required=True)
    parser.add_argument('--item-sparse-csv', type=Path, required=True)
    parser.add_argument('--calibration-tables', type=Path, required=True,
                        help='Directory with the five pinned current-build CSV inputs')
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
    client_ranges = {(int(row['Spell']), int(row['SkillLine'])): row
                     for row in read_client_table(args.skillline_ability_csv, SKILLLINE_SHA256)}
    client_items = {int(row['ID']): row for row in read_client_table(args.item_sparse_csv, ITEMSPARSE_SHA256)}

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
        path = (target / 'database' / (name + '.lua')).relative_to(repo).as_posix()
        content = subprocess.check_output(['git', '-C', str(repo), 'show', f'{PRR_AUDIT_BASELINE}:{path}'])
        runtime.execute(content.decode('utf-8-sig'))
    archive = zipfile.ZipFile(args.professiondb_zip)
    for name in (*PROFESSIONS, 'Sources', 'SourceNames', 'AcquireMethods'):
        runtime.execute(archive.read('ProfessionDB/Data/Forever/_core/' + name + '.lua').decode('utf8'))
    globals_ = runtime.globals()
    recipes, fixes = globals_.ns.Database.Recipes, globals_.ns.Database.Fixes
    details, trainers, trainer_sources, observed_ranks = {}, {}, {}, {}
    initial_skills = {}
    for spell_id, recipe in recipes.items():
        detail = {}
        core = globals_.core[spell_id]
        if core and core.profession == recipe.profession and core.requiredSkill:
            detail['skill'] = core.requiredSkill
            if globals_.borrowed.requiredSkill[spell_id]:
                detail['skillReference'] = True
        fix = fixes[spell_id]
        if fix and fix.skillUnknown:
            initial_skills[spell_id] = None
        else:
            initial_skills[spell_id] = (fix.skill if fix else None) or recipe.skill or detail.get('skill')
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

    input_hashes, baseline_hashes = {}, {}
    # Each build is a partial observation. Newer observations replace the same NPC/spell pair.
    observations, baseline_observations = {}, {}
    paths = sorted((args.forever_data / 'data/wowf').glob('*/trainers.json'),
                   key=lambda path: tuple(map(int, path.parent.name.split('.'))))
    for path in paths:
        blob = path.read_bytes()
        relative = path.relative_to(args.forever_data).as_posix()
        input_hashes[relative] = hashlib.sha256(blob).hexdigest()
        baseline = subprocess.run(['git', '-C', str(args.forever_data), 'show', AUDIT_BASELINE_COMMIT + ':' + relative],
                                  check=True, capture_output=True).stdout
        baseline_hashes[relative] = hashlib.sha256(baseline).hexdigest()
        for npc_id, npc in json.loads(baseline)['trainers'].items():
            if npc.get('tradeskill'):
                for spell_id, service in npc.get('services', {}).items():
                    baseline_observations[int(spell_id), int(npc_id)] = service
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
    baseline_ranks = {}
    for (spell_id, _), service in baseline_observations.items():
        rank = service.get('skillRank', 0)
        if rank > 0:
            baseline_ranks[spell_id] = min(rank, baseline_ranks.get(spell_id, rank))
    skill_audit = []
    for spell_id, detail in details.items():
        recipe = recipes[spell_id]
        fix = fixes[spell_id]
        if (not recipe.skill and not (fix and (fix.skill or fix.skillUnknown)) and spell_id in baseline_ranks
                and (not detail.get('skill') or detail.get('skillReference'))):
            initial_skills[spell_id] = baseline_ranks[spell_id]
        if spell_id in observed_ranks and (not detail.get('skill') or detail.get('skillReference')):
            detail['skill'] = observed_ranks[spell_id]
            detail.pop('skillReference', None)
        initial = initial_skills[spell_id]
        if initial and recipe.yellow is not None and initial > recipe.yellow:
            native = client_ranges[spell_id, recipe.profession]
            if int(native['TrivialSkillLineRankLow']) != recipe.yellow or int(native['TrivialSkillLineRankHigh']) != recipe.gray:
                raise ValueError('Client skill-up range differs from PRR for spell ' + str(spell_id))
            record = {'spellID': spell_id, 'previousSkill': initial, 'yellow': recipe.yellow,
                      'gray': recipe.gray, 'skillLineAbilityID': int(native['ID']),
                      'nativeMinimum': int(native['MinSkillLineRank'])}
            core = globals_.core[spell_id]
            verified = observed_ranks.get(spell_id)
            source = 'Forever trainer observations' if verified else None
            pattern = client_items.get(recipe.recipeItem)
            if not verified and pattern and int(pattern['RequiredSkill']) == recipe.profession:
                verified = int(pattern['RequiredSkillRank']) or None
                if verified:
                    source = 'Forever ItemSparse'
                    record['recipeItemID'] = recipe.recipeItem
            if not verified and core and core.requiredSkill and not globals_.borrowed.requiredSkill[spell_id]:
                verified = core.requiredSkill
                source = 'ProfessionDB Forever requiredSkill'
            if verified:
                record.update(skill=verified, source=source)
                if verified != initial:
                    record['status'] = 'corrected'
                    detail['skill'] = verified
                    detail.pop('skillReference', None)
                    if recipe.skill:
                        detail['skillCorrection'] = True
                else:
                    record['status'] = 'confirmedLearnAboveYellow'
            elif detail.get('skillReference'):
                record['status'] = 'rejectedReference'
                detail.pop('skill', None)
                detail.pop('skillReference', None)
            else:
                raise ValueError('Unresolved skill requirement for spell ' + str(spell_id))
            skill_audit.append(record)
        if trainer_sources[spell_id]:
            detail['trainers'] = sorted(trainer_sources[spell_id].values(),
                                        key=lambda source: (source.get('reference', False), source['npcID']))
        if (recipe.skill and not detail.get('skillCorrection')) or (fix and fix.skill):
            detail.pop('skill', None)
            detail.pop('skillReference', None)
    verification = verify_learning(repo, args, recipes, details, trainers, client_ranges, client_items)
    verified_skills = {row['spellID']: row for row in verification['unknownSkills'] if row['status'] == 'verified'}
    for record in skill_audit:
        verified = verified_skills.get(record['spellID'])
        if record['status'] == 'rejectedReference' and verified:
            status = ('confirmedLearnAboveYellow' if verified['skill'] == record['previousSkill'] else 'corrected')
            record.update(status=status, skill=verified['skill'], source=verified['source'],
                          sourceAudit='learningVerification')
    details = {id_: detail for id_, detail in details.items() if detail}
    used_trainers = {source['npcID'] for detail in details.values() for source in detail.get('trainers', [])}
    trainers = {npc_id: trainer for npc_id, trainer in trainers.items() if npc_id in used_trainers}
    faction_names = {'A': 'Alliance', 'H': 'Horde', 'AH': 'Neutral'}
    for npc_id, trainer in trainers.items():
        faction = verification['trainerFactions']['records'].get(str(npc_id))
        if faction not in faction_names:
            raise ValueError('Missing trainer faction for NPC ' + str(npc_id))
        trainer['faction'] = faction_names[faction]
    repaired = {'native': 0, 'reference': 0, 'remaining': 0}
    for spell_id, recipe in recipes.items():
        fix = fixes[spell_id]
        if (fix and fix.skill) or recipe.skill:
            continue
        detail = details.get(spell_id, {})
        key = ('reference' if detail.get('skillReference') else 'native') if detail.get('skill') else 'remaining'
        repaired[key] += 1
    calibration, calibration_audit = calibrate_skills(
        args, recipes, fixes, details, verification, globals_.core, globals_.borrowed.requiredSkill)
    for name in ('recipes', 'fixes'):
        runtime.execute((target / 'database' / (name + '.lua')).read_text(encoding='utf-8-sig'))
    adopted_recipes, adopted_fixes = globals_.ns.Database.Recipes, globals_.ns.Database.Fixes
    adopted_source = json.loads((target / 'SOURCE.json').read_text(encoding='utf-8-sig'))
    # Keep the historical audit records intact when trimming the runtime overlay.
    calibration = {spell_id: fields.copy() for spell_id, fields in calibration.items()}
    absorbed = remove_absorbed_corrections(details, calibration, adopted_recipes, adopted_fixes)
    details = {spell_id: detail for spell_id, detail in details.items() if detail}
    calibration = {spell_id: fields for spell_id, fields in calibration.items() if fields}
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
    lines.extend(['}', 'ns.Database.RecipeCalibration = {'])
    for spell_id, fields in sorted(calibration.items()):
        lines.append('    [' + str(spell_id) + '] = ' + lua(fields) + ',')
    lines.extend(['}', 'end)', ''])
    write_utf8(target / 'database/recipe_details.lua', '\n'.join(lines))
    write_utf8(target / 'LICENSE-ProfessionDB.txt', archive.read('ProfessionDB/LICENSE').decode('utf8').rstrip() + '\n')
    write_utf8(target / 'LICENSE-EfficientGames.txt', (args.forever_data / 'LICENSE').read_text(encoding='utf8').rstrip() + '\n')
    provenance = {
        'updatedAt': '2026-11-27',
        'prrUpstreamMerge': {
            'auditBaselineCommit': PRR_AUDIT_BASELINE,
            'adoptedVersion': adopted_source['version'],
            'adoptedPackageSHA256': adopted_source['packageSHA256'],
            'addedSpellIDs': sorted(set(adopted_recipes) - set(recipes)),
            'absorbed': absorbed,
        },
        'professionDB': {'version': '1.10.1', 'license': 'MIT', 'author': 'Pimptasty',
                         'release': 'https://www.curseforge.com/wow/addons/libprofessiondb/files/9653856',
                         'packageSHA256': PROFESSIONDB_SHA256, 'data': 'Data/Forever/_core'},
        'efficientGames': {'repository': 'https://github.com/JIVESCORP/eg-link-output-wowf',
                           'commit': FOREVER_COMMIT, 'license': 'CC BY 4.0',
                           'attribution': 'Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0.',
                           'inputs': input_hashes},
        'skillAuditBaseline': {'efficientGamesCommit': AUDIT_BASELINE_COMMIT, 'inputs': baseline_hashes},
        'transformation': [
            'Export only spell IDs already present in PRR, and only the Forever data tree.',
            'Fill missing requirements from native library data, observed Forever trainers, then flagged Vanilla references.',
            'Audit requirements above the native yellow threshold against trainers, native recipe items and own-flavor library data.',
            'Correct verified differences and reject conflicting borrowed requirements. Confirmed learn requirements can exceed yellow.',
            'Runtime applies verified base corrections and supplements below explicit PRR/user fixes.',
            'Corroborate imported trainer IDs against Forever observations and explicit recipe-specific documentation.',
            'Exclude unverified Wrath/Cataclysm emulator trainer pairs from runtime locations and retain their audit records.',
            'Use current-build player trainer captures for missing learning requirements and review trainer identity separately.',
            'Review every remaining unknown at the c16642d baseline and retain exact-source conflicts and unresolved teaching routes.',
            'Classify each runtime trainer by player faction using the pinned Forever NPC metadata and documented neutral overrides.',
        ],
        'clientTables': {
            'build': CLIENT_BUILD,
            'SkillLineAbility': {'url': 'https://wago.tools/db2/SkillLineAbility/csv?build=' + CLIENT_BUILD,
                                 'sha256': SKILLLINE_SHA256},
            'ItemSparse': {'url': 'https://wago.tools/db2/ItemSparse/csv?build=' + CLIENT_BUILD,
                           'sha256': ITEMSPARSE_SHA256},
            **{name: {'url': 'https://wago.tools/db2/' + name + '/csv?build=' + CLIENT_BUILD, 'sha256': digest}
               for name, digest in TEACHING_TABLES.items()},
        },
        'learningVerification': verification,
        'skillCalibration': calibration_audit,
        'skillAudit': sorted(skill_audit, key=lambda row: row['spellID']),
        'npcNameCorrections': {'source': 'QuestieDB 1.1.1 NPC records bundled with Raynna Bestiary',
                               'release': 'https://github.com/Questie/QuestieDB/releases/tag/v1.1.1',
                               'names': TRAINER_NAMES},
        'coverage': {'recipes': len(details), 'trainers': len(trainers),
                     'trainerRecipes': sum(bool(detail.get('trainers')) for detail in details.values()),
                     'trainerFactions': {name: sum(trainer['faction'] == name for trainer in trainers.values())
                                         for name in faction_names.values()},
                     'missingSkills': repaired,
                     'learningVerification': {
                         'unknownSkillsChecked': len(verification['unknownSkills']),
                         'skillsVerified': sum(row['status'] == 'verified' for row in verification['unknownSkills']),
                         'localSkillsVerified': len(verification['localTrainerCaptures']['records']),
                         'reviewedTrainerRecipes': len(verification['recipeTrainerReviews']['recipes']),
                         'referenceRecipesChecked': len(verification['referenceTrainers']),
                         'referencePairsChecked': sum(len(row[key]) for row in verification['referenceTrainers']
                                                      for key in ('verifiedDocumentationNPCIDs', 'verifiedBetaNPCIDs',
                                                                  'rejectedCrossExpansionNPCIDs')),
                         'referencePairsVerified': sum(len(row['verifiedDocumentationNPCIDs'])
                                                       + len(row['verifiedBetaNPCIDs'])
                                                       for row in verification['referenceTrainers']),
                         'rejectedReferencePairs': sum(len(row['rejectedCrossExpansionNPCIDs'])
                                                       for row in verification['referenceTrainers']),
                         'remainingReferencePairs': sum(bool(source.get('reference')) for detail in details.values()
                                                        for source in detail.get('trainers', [])),
                         'questionMarksChecked': len(verification['questionMarkReview']['records']),
                         'questionMarksVerified': sum(row['status'] == 'verified'
                                                      for row in verification['questionMarkReview']['records']),
                     },
                     'skillAudit': {status: sum(row['status'] == status for row in skill_audit)
                                    for status in ('corrected', 'rejectedReference', 'confirmedLearnAboveYellow')}},
    }
    write_utf8(target / 'RECIPE-SOURCES.json', json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(provenance['coverage'], ensure_ascii=False))


if __name__ == '__main__':
    main()
