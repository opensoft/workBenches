#!/usr/bin/env python3
"""Validate presentation metadata and compile static, non-executable snapshots."""
import argparse
import json
from pathlib import Path
import pprint
import re
import shlex
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from setup_harnesses import registry
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'config/setup-tool-catalog.json'
BASH = ROOT / 'scripts/lib/setup-tool-catalog.generated.sh'
PYTHON = ROOT / 'scripts/setup_tool_catalog_data.py'
BASE_MANAGED = {'claude_cli', 'copilot_cli', 'codex_cli', 'antigravity_cli', 'opencode_cli', 'pi_cli',
           'spec_kit', 'openspec', 'vscode', 'warp', 'wave', 'amnezia_vpn', '0dcloud_vpn', 'host_shell', 'workspace_repo'}
INSTALLERS = registry()
MANAGED = BASE_MANAGED | {key for key, row in INSTALLERS.items() if row['kind'] != 'unavailable'}
IDENTIFIER = re.compile(r'^[a-z0-9][a-z0-9_]*$')
COMMAND = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._+-]*$')
CAPABILITIES = {'interactive', 'noninteractive', 'scriptableIO', 'modelSupport', 'autonomy', 'permissions'}
INTEROP = {'invokesAgents', 'externallyInvoked', 'delegation', 'stateExchange', 'parallelExecution'}
ENTRY_FIELDS = {'id', 'label', 'section', 'category', 'cliGroup', 'managed', 'developer', 'developerRelationship',
                'developerRegion', 'modelPolicy', 'terminalInterface', 'executionLocation', 'productStatus', 'lineage',
                'additionalSurfaces', 'tags', 'about', 'capabilities', 'interoperability', 'verification', 'detection', 'filters'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_text(value, label, *, multiline=False):
    require(isinstance(value, str) and value.strip(), label + ': expected nonempty text')
    require(not any(ord(c) < 32 and not (multiline and c == '\n') or 127 <= ord(c) <= 159 for c in value), label + ': control character')
    require(not re.search(r'(?:/home/[^/\s]+/|/workspace/|[A-Za-z]:\\Users\\)', value), label + ': workstation path')


def text_list(values, label):
    require(isinstance(values, list) and len(values) == len(set(values)), label + ': expected unique list')
    for value in values:
        safe_text(value, label)


def validate(data):
    require(isinstance(data, dict) and data.get('schemaVersion') == 2, 'invalid catalog schema')
    require(set(data) == {'schemaVersion', 'legacyReferenceOrder', 'categories', 'cliGroups', 'entries', 'frontierLabs', 'filterFacets'}, 'unknown catalog fields')
    require(set(data['categories']) == {'harness', 'tool'}, 'invalid catalog sections')
    categories = {}
    for family, rows in data['categories'].items():
        require(isinstance(rows, list) and rows, 'empty category list')
        categories[family] = set()
        for row in rows:
            require(set(row) == {'id', 'label', 'summary'} and IDENTIFIER.fullmatch(row['id']), 'invalid category')
            require(row['id'] not in categories[family], 'duplicate category')
            categories[family].add(row['id'])
            safe_text(row['label'], 'category label'); safe_text(row['summary'], 'category summary')
    groups = set()
    for row in data['cliGroups']:
        require(set(row) == {'id', 'label', 'summary'} and IDENTIFIER.fullmatch(row['id']), 'invalid CLI group')
        require(row['id'] not in groups, 'duplicate CLI group')
        groups.add(row['id']); safe_text(row['label'], 'group label'); safe_text(row['summary'], 'group summary')
    require('all' in groups, 'missing all group')
    lab_ids = set()
    for lab in data['frontierLabs']:
        require(set(lab) == {'id', 'label', 'recorded', 'note'} and IDENTIFIER.fullmatch(lab['id']) and lab['id'] not in lab_ids, 'invalid frontier lab')
        lab_ids.add(lab['id'])
        for key in ('label', 'note', 'recorded'): safe_text(lab[key], 'frontier lab:' + key)
        require(re.fullmatch(r'20\d\d-\d\d-\d\d', lab['recorded']), 'invalid frontier curation date')
    facets = {}
    for facet in data['filterFacets']:
        require(set(facet) == {'id', 'label', 'summary', 'options'} and facet['id'] not in facets and IDENTIFIER.fullmatch(facet['id']), 'invalid filter facet')
        safe_text(facet['label'], 'facet label'); safe_text(facet['summary'], 'facet summary')
        options = set()
        for option in facet['options']:
            require(set(option) == {'id', 'label'} and IDENTIFIER.fullmatch(option['id']) and option['id'] not in options, 'invalid facet option')
            options.add(option['id']); safe_text(option['label'], 'facet option label')
        require('unknown' in options, 'facet must expose unknown metadata')
        facets[facet['id']] = options
    require(list(facets) == ['type', 'region', 'access', 'native'], 'invalid facet dimensions/order')
    require(facets['type'] == {'frontier', 'open', 'closed', 'all', 'unknown'} and facets['region'] == {'all', 'usa', 'china', 'other', 'unknown'}, 'invalid type/region options')
    require(facets['access'] == {'all', 'subscription', 'api', 'local', 'unknown'}, 'invalid access options')
    require(facets['native'] == {'all', 'llm', 'image', 'video', 'voice', 'classifier', 'unknown'}, 'invalid capability options')
    entries = data['entries']; require(isinstance(entries, list) and entries, 'empty catalog')
    ids = set(); labels = set(); managed = set(); by_id = {}
    for entry in entries:
        require(isinstance(entry, dict) and set(entry) == ENTRY_FIELDS, 'invalid entry fields')
        key = entry['id']; require(isinstance(key, str) and IDENTIFIER.fullmatch(key) and key not in ids, 'invalid/duplicate entry ID')
        ids.add(key); by_id[key] = entry
        require(entry['section'] in categories and entry['category'] in categories[entry['section']], key + ': invalid category')
        is_cli = entry['section'] == 'harness' and entry['category'] == 'tui'
        require(entry['cliGroup'] in groups - {'all'} if is_cli else entry['cliGroup'] is None, key + ': invalid CLI ownership group')
        facts = entry['filters']
        if not is_cli:
            require(facts is None, key + ': filters are CLI-only')
        else:
            require(isinstance(facts, dict) and set(facts) == {'frontierLab', 'access', 'native', 'via', 'models'}, key + ': invalid filter facts')
            require(facts['frontierLab'] is None or facts['frontierLab'] in lab_ids, key + ': unknown frontier lab')
            for facet in ('access', 'native', 'via', 'models'):
                record = facts[facet]
                require(isinstance(record, dict) and set(record) == {'values', 'complete', 'basis', 'note', 'sources', 'recorded'}, key + ': invalid facet record')
                text_list(record['values'], key + ':' + facet)
                allowed = {'open', 'closed'} if facet == 'models' else facets['native' if facet == 'via' else facet] - {'unknown', 'all'}
                require(set(record['values']) <= allowed, key + ': invalid facet value')
                require(type(record['complete']) is bool, key + ': invalid completeness')
                require(record['basis'] in {'primary-source', 'user-provided', 'documented-route', 'unverified'}, key + ': invalid filter provenance')
                require(record['basis'] != 'unverified' or not record['values'], key + ': unverified positive filter values')
                safe_text(record['note'], key + ':filter note'); safe_text(record['recorded'], key + ':filter date')
                require(re.fullmatch(r'20\d\d-\d\d-\d\d', record['recorded']), key + ': invalid filter date')
                text_list(record['sources'], key + ':filter sources')
                require(record['basis'] not in {'primary-source', 'documented-route'} or record['sources'], key + ': missing filter evidence')
                for url in record['sources']:
                    require(urlparse(url).scheme == 'https' and urlparse(url).netloc and not any(c.isspace() for c in url), key + ': invalid filter source')
        require(type(entry['managed']) is bool, key + ': managed must be boolean')
        if entry['managed']: managed.add(key)
        for name in ('label', 'developer', 'developerRelationship', 'developerRegion', 'modelPolicy', 'executionLocation', 'productStatus', 'lineage'):
            safe_text(entry[name], key + ':' + name)
        require(entry['label'] not in labels, 'ambiguous duplicate product label'); labels.add(entry['label'])
        require(entry['developerRelationship'] in {'model-maker', 'corporate-affiliate', 'independent', 'unverified'}, key + ': invalid relationship')
        require(entry['developerRegion'] in {'USA', 'China', 'Other', 'unverified'}, key + ': invalid region')
        require(entry['modelPolicy'] in {'own-model-centered', 'selectable-providers', 'managed-routing', 'unverified'}, key + ': invalid model policy')
        require(entry['executionLocation'] in {'local', 'remote', 'both', 'unverified'}, key + ': invalid execution location')
        require(entry['productStatus'] in {'current', 'preview', 'transitioning', 'maintenance-uncertain', 'unverified'}, key + ': invalid product status')
        require(entry['lineage'] in {'original', 'fork', 'wrapper', 'unverified'}, key + ': invalid lineage')
        for name in ('terminalInterface', 'additionalSurfaces', 'tags'): text_list(entry[name], key + ':' + name)
        safe_text(entry['about'], key + ':about', multiline=True)
        for name, fields in (('capabilities', CAPABILITIES), ('interoperability', INTEROP)):
            require(isinstance(entry[name], dict) and set(entry[name]) == fields, key + ': invalid ' + name)
            for field in fields: safe_text(entry[name][field], key + ':' + field)
        v = entry['verification']
        require(set(v) == {'basis', 'note', 'evidence', 'capabilityEvidence', 'recorded'}, key + ': invalid verification')
        require(v['basis'] in {'user-provided', 'existing-catalog', 'primary-source'}, key + ': invalid evidence basis')
        safe_text(v['note'], key + ':evidence note')
        require(re.fullmatch(r'20\d\d-\d\d-\d\d', v['recorded']), key + ': invalid evidence date')
        for field in ('evidence', 'capabilityEvidence'):
            text_list(v[field], key + ':' + field)
            for url in v[field]: require(urlparse(url).scheme == 'https' and urlparse(url).netloc and not any(c.isspace() for c in url), key + ': invalid evidence URL')
        d = entry['detection']
        require(set(d) == {'commands', 'desktopIds', 'extensionIds', 'npmPackage'}, key + ': invalid detection')
        for field in ('commands', 'desktopIds', 'extensionIds'):
            text_list(d[field], key + ':' + field)
            for value in d[field]: require(COMMAND.fullmatch(value), key + ': detection must be an identifier, not a shell command/path')
        require(all(v.endswith('.desktop') for v in d['desktopIds']), key + ': invalid desktop ID')
        require(d['npmPackage'] is None or re.fullmatch(r'(?:@[a-z0-9-]+/)?[a-z0-9.-]+', d['npmPackage']), key + ': invalid package ID')
    require(set(INSTALLERS) == {e['id'] for e in entries if e['section'] == 'harness' and e['category'] == 'tui' and e['id'] not in BASE_MANAGED}, 'installer registry must cover only the additional terminal inventory')
    require(managed == MANAGED, 'managed plan keys cannot change with catalog metadata')
    require(set(data['legacyReferenceOrder']) == {'harness', 'tool'}, 'missing legacy reference order')
    for family, order in data['legacyReferenceOrder'].items():
        text_list(order, 'legacy refs')
        for key in order: require(key in by_id and by_id[key]['section'] == family and key not in BASE_MANAGED, 'invalid legacy reference order')
    for family, category_ids in categories.items():
        for category in category_ids: require(any(e['section'] == family and e['category'] == category for e in entries), 'empty category')
    for group in groups - {'all'}: require(any(e['cliGroup'] == group for e in entries), 'empty CLI group')
    return data


def about(entry):
    c = entry['capabilities']; i = entry['interoperability']; v = entry['verification']
    qualifier = 'User inventory' if v['basis'] == 'user-provided' else 'Catalog entry' if v['basis'] == 'existing-catalog' else 'Documented entry'
    lines = [qualifier + ' · ' + entry['about'], '', 'Catalog basis: ' + v['basis'] + '. ' + v['note'],
             'Developer: ' + entry['developer'], 'Developer relationship: ' + entry['developerRelationship'],
             'Developer region: ' + entry['developerRegion'], 'Model policy: ' + entry['modelPolicy'],
             'Tags: ' + ', '.join(entry['tags']), 'Terminal modes: ' + ', '.join(entry['terminalInterface']),
             'Execution location: ' + entry['executionLocation'], 'Product status: ' + entry['productStatus'],
             'Lineage: ' + entry['lineage'], 'Additional surfaces: ' + (', '.join(entry['additionalSurfaces']) or 'Not yet cataloged'),
             'Interactive interface: ' + c['interactive'], 'Noninteractive execution: ' + c['noninteractive'],
             'Scriptable input/output: ' + c['scriptableIO'], 'Model support: ' + c['modelSupport'],
             'Autonomy: ' + c['autonomy'], 'Permissions: ' + c['permissions'], '', 'Agent interoperability:',
             'Invokes another agent: ' + i['invokesAgents'], 'Can be invoked externally: ' + i['externallyInvoked'],
             'Delegation model: ' + i['delegation'], 'State exchange: ' + i['stateExchange'], 'Parallel execution: ' + i['parallelExecution']]
    if entry['filters']:
        facts = entry['filters']
        filter_summary = 'Filter tags: ' + ('Frontier (curated)' if facts['frontierLab'] else 'Frontier unclassified') + ' · ' + entry['developerRegion']
        for facet, label in (('access', 'Access'), ('native', 'Native'), ('via', 'Via')):
            filter_summary += ' · ' + label + ': ' + ('/'.join(facts[facet]['values']) or 'Unknown')
        filter_summary += ' · Models: ' + ('/'.join(facts['models']['values']) or 'Unknown')
        lines.insert(1, filter_summary)
        lines += ['', 'Filter Frontier: ' + (facts['frontierLab'] or 'Unclassified') + ' (curated lab membership, not a model ranking)',
                  'Filter region: ' + entry['developerRegion']]
        for facet, label in (('access', 'Access methods'), ('native', 'Native workloads'), ('via', 'Via models/plugins'), ('models', 'Model weights')):
            record = facts[facet]
            lines.append(label + ': ' + (', '.join(record['values']) or 'Unknown') + ' [' + record['basis'] + ('; partial' if not record['complete'] else '') + ']')
            lines.append('Scope: ' + record['note'])
            for source in record['sources']: lines.append('Filter evidence: ' + source)
    if entry['id'] in INSTALLERS:
        recipe = INSTALLERS[entry['id']]
        lines += ['', ('Automatic install/update/removal available; command: ' + recipe.get('command', '') if recipe['kind'] != 'unavailable' else 'Unavailable: ' + recipe['note']),
                  'Installation does not establish login or account access.', 'Installer source: ' + recipe['source']]
    if not entry['managed']:
        lines += ['', 'Manual setup: manage installation/update/removal with the original publisher or installer; this wizard does not manage this entry.',
                  'Presence does not establish login, account access or documented feature availability.']
    for url in v['evidence']: lines.append('Setup/source: ' + url)
    for url in v['capabilityEvidence']: lines.append('Capability evidence: ' + url)
    if not v['evidence'] and not v['capabilityEvidence']:
        lines.append('Source: user-supplied inventory; independent publisher/setup link not yet verified.')
    return '\n'.join(lines)


def filter_values(entry, facet):
    facts = entry['filters']
    if facet == 'frontier': return 'frontier' if facts['frontierLab'] else 'unknown'
    if facet == 'type':
        return ' '.join((['frontier'] if facts['frontierLab'] else []) + facts['models']['values'] + ([] if facts['models']['complete'] else ['unknown']))
    if facet == 'region': return {'USA': 'usa', 'China': 'china', 'Other': 'other'}.get(entry['developerRegion'], 'unknown')
    record = facts[facet]
    return ' '.join(record['values'] + ([] if record['complete'] else ['unknown']))


def snapshots(data):
    entries = data['entries']; shell = ['# Generated by scripts/setup-tool-catalog.py; edit config/setup-tool-catalog.json.', '# Static data only; no runtime parsing or product execution.']
    def array(name, values): shell.append('declare -a ' + name + '=(' + ' '.join(shlex.quote(value) for value in values) + ')')
    def mapping(name, values):
        shell.append('declare -A ' + name + '=(')
        shell.extend('    [' + key + ']=' + shlex.quote(value) for key, value in values.items())
        shell.append(')')
    for family in ('harness', 'tool'):
        refs = data['legacyReferenceOrder'][family][:]
        refs += [e['id'] for e in entries if e['section'] == family and e['id'] not in BASE_MANAGED and e['id'] not in refs]
        array('setup_catalog_' + family + '_refs', refs)
        rows = data['categories'][family]
        array('setup_' + family + '_categories', [r['id'] for r in rows])
        mapping('setup_' + family + '_labels', {r['id']: r['label'] for r in rows})
        mapping('setup_' + family + '_summaries', {r['id']: r['summary'] for r in rows})
        mapping('setup_' + family + '_members', {r['id']: ' '.join(e['id'] for e in entries if e['section'] == family and e['category'] == r['id']) for r in rows})
    groups = data['cliGroups']
    array('setup_cli_groups', [r['id'] for r in groups])
    mapping('setup_cli_group_labels', {r['id']: r['label'] for r in groups})
    mapping('setup_cli_group_summaries', {r['id']: r['summary'] for r in groups})
    mapping('setup_cli_group_members', {r['id']: ' '.join(e['id'] for e in entries if e['category'] == 'tui' and e['section'] == 'harness' and (r['id'] == 'all' or e['cliGroup'] == r['id'])) for r in groups})
    facet_rows = data['filterFacets']
    array('setup_cli_filter_rows', [r['id'] for r in facet_rows])
    mapping('setup_cli_filter_labels', {r['id']: r['label'] for r in facet_rows})
    mapping('setup_cli_filter_summaries', {r['id']: r['summary'] for r in facet_rows})
    mapping('setup_cli_filter_options', {r['id']: ' '.join(o['id'] for o in r['options']) for r in facet_rows})
    mapping('setup_cli_filter_option_labels', {r['id'] + ':' + o['id']: o['label'] for r in facet_rows for o in r['options']})
    cli_entries = [e for e in entries if e['section'] == 'harness' and e['category'] == 'tui']
    mapping('setup_cli_filter_values', {e['id'] + ':' + facet: filter_values(e, facet) for e in cli_entries for facet in ('type', 'region', 'access', 'native', 'via')})
    mapping('setup_cli_filter_lab_labels', {r['id']: r['label'] for r in data['frontierLabs']})
    mapping('setup_catalog_labels', {e['id']: e['label'] for e in entries})
    mapping('setup_reference_labels', {e['id']: e['label'] for e in entries if not e['managed']})
    mapping('setup_managed_harnesses', {key: row['command'] for key, row in INSTALLERS.items() if row['kind'] != 'unavailable'})
    mapping('setup_harness_node_dependencies', {key: 'true' for key, row in INSTALLERS.items() if row['kind'] in {'npm', 'git-node'} or row.get('shell') == 'node' or row.get('tuiPackage')})
    mapping('component_about', {e['id']: about(e) for e in entries})
    detection = {e['id']: e['detection'] for e in entries if e['id'] not in BASE_MANAGED}
    python = '# Generated by scripts/setup-tool-catalog.py; edit config/setup-tool-catalog.json.\nREFERENCE_DETECTION = ' + pprint.pformat(detection, sort_dicts=False, width=100) + '\n'
    return '\n'.join(shell) + '\n', python


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--check', action='store_true'); group.add_argument('--write', action='store_true')
    args = parser.parse_args()
    data = validate(json.loads(CATALOG.read_text()))
    for path, expected in zip((BASH, PYTHON), snapshots(data)):
        if args.check: require(path.exists() and path.read_text() == expected, 'stale generated catalog: ' + str(path.relative_to(ROOT)))
        else: path.write_text(expected)
    for relative in ('scripts/setup_harnesses.py', 'scripts/setup_harness_targets.py', 'scripts/setup-harnesses.py', 'scripts/harness-native-command.sh', 'config/harness-installers.json'):
        source = ROOT / relative
        target = ROOT / 'user-layer/harness-runtime' / relative
        if args.check: require(target.exists() and target.read_bytes() == source.read_bytes(), 'stale image harness runtime: ' + relative)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
    selection = ROOT / 'user-layer/harness-runtime/selection.list'
    if args.check: require(selection.exists() and selection.read_bytes() == b'', 'default image harness selection must be empty')
    else: selection.write_bytes(b'')
    print('Tool catalog valid: ' + str(len(data['entries'])) + ' distinct products; snapshots ' + ('match' if args.check else 'written'))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        print('Invalid tool catalog: ' + str(error), file=sys.stderr); sys.exit(1)
