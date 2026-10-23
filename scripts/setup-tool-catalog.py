#!/usr/bin/env python3
"""Validate presentation metadata and compile static, non-executable snapshots."""
import argparse
import json
from pathlib import Path
import pprint
import re
import shlex
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'config/setup-tool-catalog.json'
BASH = ROOT / 'scripts/lib/setup-tool-catalog.generated.sh'
PYTHON = ROOT / 'scripts/setup_tool_catalog_data.py'
MANAGED = {'claude_cli', 'copilot_cli', 'codex_cli', 'antigravity_cli', 'opencode_cli', 'pi_cli',
           'spec_kit', 'openspec', 'vscode', 'warp', 'wave', 'amnezia_vpn', '0dcloud_vpn', 'host_shell', 'workspace_repo'}
IDENTIFIER = re.compile(r'^[a-z0-9][a-z0-9_]*$')
COMMAND = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._+-]*$')
CAPABILITIES = {'interactive', 'noninteractive', 'scriptableIO', 'modelSupport', 'autonomy', 'permissions'}
INTEROP = {'invokesAgents', 'externallyInvoked', 'delegation', 'stateExchange', 'parallelExecution'}
ENTRY_FIELDS = {'id', 'label', 'section', 'category', 'cliGroup', 'managed', 'developer', 'developerRelationship',
                'developerRegion', 'modelPolicy', 'terminalInterface', 'executionLocation', 'productStatus', 'lineage',
                'additionalSurfaces', 'tags', 'about', 'capabilities', 'interoperability', 'verification', 'detection'}


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
    require(isinstance(data, dict) and data.get('schemaVersion') == 1, 'invalid catalog schema')
    require(set(data) == {'schemaVersion', 'legacyReferenceOrder', 'categories', 'cliGroups', 'entries'}, 'unknown catalog fields')
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
    entries = data['entries']; require(isinstance(entries, list) and entries, 'empty catalog')
    ids = set(); labels = set(); managed = set(); by_id = {}
    for entry in entries:
        require(isinstance(entry, dict) and set(entry) == ENTRY_FIELDS, 'invalid entry fields')
        key = entry['id']; require(isinstance(key, str) and IDENTIFIER.fullmatch(key) and key not in ids, 'invalid/duplicate entry ID')
        ids.add(key); by_id[key] = entry
        require(entry['section'] in categories and entry['category'] in categories[entry['section']], key + ': invalid category')
        is_cli = entry['section'] == 'harness' and entry['category'] == 'tui'
        require(entry['cliGroup'] in groups - {'all'} if is_cli else entry['cliGroup'] is None, key + ': invalid CLI ownership group')
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
    require(managed == MANAGED, 'managed plan keys cannot change with catalog metadata')
    require(set(data['legacyReferenceOrder']) == {'harness', 'tool'}, 'missing legacy reference order')
    for family, order in data['legacyReferenceOrder'].items():
        text_list(order, 'legacy refs')
        for key in order: require(key in by_id and by_id[key]['section'] == family and not by_id[key]['managed'], 'invalid legacy reference order')
    for family, category_ids in categories.items():
        for category in category_ids: require(any(e['section'] == family and e['category'] == category for e in entries), 'empty category')
    for group in groups - {'all'}: require(any(e['cliGroup'] == group for e in entries), 'empty CLI group')
    return data


def about(entry):
    c = entry['capabilities']; i = entry['interoperability']; v = entry['verification']
    lines = [entry['about'], '', 'Catalog basis: ' + v['basis'] + '. ' + v['note'],
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
    if not entry['managed']:
        lines += ['', 'Manual setup: manage installation/update/removal with the original publisher or installer; this wizard does not manage this entry.',
                  'Presence does not establish login, account access or documented feature availability.']
    for url in v['evidence']: lines.append('Setup/source: ' + url)
    for url in v['capabilityEvidence']: lines.append('Capability evidence: ' + url)
    if not v['evidence'] and not v['capabilityEvidence']:
        lines.append('Source: user-supplied inventory; independent publisher/setup link not yet verified.')
    return '\n'.join(lines)


def snapshots(data):
    entries = data['entries']; shell = ['# Generated by scripts/setup-tool-catalog.py; edit config/setup-tool-catalog.json.', '# Static data only; no runtime parsing or product execution.']
    def array(name, values): shell.append('declare -a ' + name + '=(' + ' '.join(shlex.quote(value) for value in values) + ')')
    def mapping(name, values):
        shell.append('declare -A ' + name + '=(')
        shell.extend('    [' + key + ']=' + shlex.quote(value) for key, value in values.items())
        shell.append(')')
    for family in ('harness', 'tool'):
        refs = data['legacyReferenceOrder'][family][:]
        refs += [e['id'] for e in entries if e['section'] == family and not e['managed'] and e['id'] not in refs]
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
    mapping('setup_catalog_labels', {e['id']: e['label'] for e in entries})
    mapping('setup_reference_labels', {e['id']: e['label'] for e in entries if not e['managed']})
    mapping('component_about', {e['id']: about(e) for e in entries})
    detection = {e['id']: e['detection'] for e in entries if not e['managed']}
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
    print('Tool catalog valid: ' + str(len(data['entries'])) + ' distinct products; snapshots ' + ('match' if args.check else 'written'))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        print('Invalid tool catalog: ' + str(error), file=sys.stderr); sys.exit(1)
