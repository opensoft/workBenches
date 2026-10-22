#!/usr/bin/env python3
"""Validate the wizard catalog contract and copy using only the standard library."""
import copy
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unicodedata
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / 'specs/029-setup-guided-wizard/contracts/bench-config.schema.json').read_text())


def structural(value, rule, where, errors):
    if '$ref' in rule:
        target = SCHEMA
        for key in rule['$ref'].removeprefix('#/').split('/'):
            target = target[key]
        structural(value, target, where, errors)
    for child in rule.get('allOf', []):
        structural(value, child, where, errors)
    kind = rule.get('type')
    valid = {'object': isinstance(value, dict), 'array': isinstance(value, list),
             'string': isinstance(value, str), 'integer': type(value) is int}
    if kind and not valid[kind]:
        errors.append(f'{where}: expected {kind}'); return
    if 'enum' in rule and value not in rule['enum']:
        errors.append(f'{where}: invalid value {value!r}')
    if 'const' in rule and value != rule['const']:
        errors.append(f'{where}: expected {rule["const"]!r}')
    if isinstance(value, dict):
        for key in rule.get('required', []):
            if key not in value: errors.append(f'{where}: missing {key}')
        properties = rule.get('properties', {})
        for key, entry in value.items():
            if 'propertyNames' in rule: structural(key, rule['propertyNames'], f'{where}.{key}', errors)
            if key in properties: structural(entry, properties[key], f'{where}.{key}', errors)
            elif rule.get('additionalProperties') is False: errors.append(f'{where}: unexpected {key}')
            elif isinstance(rule.get('additionalProperties'), dict):
                structural(entry, rule['additionalProperties'], f'{where}.{key}', errors)
    if isinstance(value, list):
        if len(value) < rule.get('minItems', 0): errors.append(f'{where}: empty list')
        for index, item in enumerate(value): structural(item, rule.get('items', {}), f'{where}[{index}]', errors)
    if isinstance(value, str):
        if not value.strip() or value == '-': errors.append(f'{where}: empty or reserved text')
        if len(value) < rule.get('minLength', 0) or len(value) > rule.get('maxLength', len(value)):
            errors.append(f'{where}: invalid length {len(value)}')
        # The schema's line pattern is additionally enforced by Unicode rules below.
        pattern = rule.get('pattern')
        if pattern and '\\u' not in pattern and not re.search(pattern, value): errors.append(f'{where}: invalid pattern {value!r}')
        forbidden = rule.get('not', {})
        if value == forbidden.get('const'): errors.append(f'{where}: reserved value')
        if 'pattern' in forbidden and re.search(forbidden['pattern'], value): errors.append(f'{where}: forbidden path {value}')


def check_text(value, where, errors, versions=False):
    if not isinstance(value, str): return
    for c in value:
        if unicodedata.category(c).startswith(('C', 'M')) or unicodedata.east_asian_width(c) in ('W', 'F'):
            errors.append(f'{where}: unsupported character U+{ord(c):04X}')
    if versions:
        value = value.replace('Microsoft 365', 'Microsoft').replace('Dynamics 365', 'Dynamics')
        token = re.search(r'(?<![A-Za-z0-9])(?:version-|v)?\d+(?:\.\d+)*(?![A-Za-z0-9])', value)
        if token: errors.append(f'{where}: version token {token[0]}')


def validate(catalog, lock):
    errors = []
    structural(catalog, SCHEMA, 'catalog', errors)
    categories = catalog.get('categories', {})
    benches = catalog.get('benches', {})
    counts = dict.fromkeys(categories, 0)
    for name, item in categories.items():
        for field in ('label', 'summary'): check_text(item.get(field), f'{name}.{field}', errors)
    for name, item in benches.items():
        category = item.get('category')
        if category not in categories: errors.append(f'{name}: unknown category {category}')
        else: counts[category] += 1
        for field in ('tagline', 'description'):
            check_text(item.get(field), f'{name}.{field}', errors, field == 'tagline')
        for field in ('usedFor', 'contains'):
            if isinstance(item.get(field), list):
                for text in item[field]: check_text(text, f'{name}.{field}', errors, True)
    for name, count in counts.items():
        if (name == 'electrical-engineering' and count) or (name != 'electrical-engineering' and not count):
            errors.append(f'{name}: invalid bench count {count}')
    expected = {item['path']: item['url'] for item in lock['repositories']}
    actual = {item.get('path'): item.get('url') for item in benches.values()}
    for path in expected.keys() | actual.keys():
        if expected.get(path) != actual.get(path): errors.append(f'{path}: release lock mismatch')
    if len(actual) != len(benches): errors.append('catalog: duplicate bench paths')
    sim = benches.get('simBench', {})
    text = ' '.join([sim.get('tagline', ''), sim.get('description', ''), *sim.get('contains', [])])
    for name in ('OpenMM', 'ESM'):
        if name not in text: errors.append(f'simBench: missing {name}')
    if re.search('AlphaFold|ESMFold', text, re.I): errors.append('simBench: unsupported bundled models')
    return errors


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads((ROOT / 'config/bench-config.json').read_text())
        self.lock = json.loads((ROOT / 'config/release-lock.json').read_text())

    def test_real_catalog_matches_contract(self):
        self.assertEqual(validate(self.catalog, self.lock), [])
        self.assertEqual(len(self.catalog['benches']), 12)

    def test_negative_copy_fixtures_name_bench_and_token(self):
        for field, text, diagnostic in [('tagline', 'x'*36, 'length'), ('tagline', 'Ａ', 'FF21'),
                                         ('tagline', 'zero\u200bwidth', '200B'),
                                         ('contains', 'Go 1.26 toolchain', '1.26'),
                                         ('tagline', 'bad\x1b[2J', '001B'),
                                         ('tagline', 'v2', 'v2'), ('tagline', 'version-4', 'version-4')]:
            with self.subTest(text=text):
                catalog = copy.deepcopy(self.catalog)
                catalog['benches']['goBench'][field] = [text] if field == 'contains' else text
                errors = validate(catalog, self.lock)
                self.assertTrue(any('goBench' in e and diagnostic in e for e in errors), errors)

    def test_product_numbers_are_allowed(self):
        errors = []
        for text in ('Microsoft 365', 'Dynamics 365', 'ARM64', 'MMseqs2', 'py3Dmol', 'm365'):
            check_text(text, '365Bench', errors, True)
        self.assertEqual(errors, [])

    def test_real_selection_accepts_365bench(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'selection.json'
            p.write_text(json.dumps({'schemaVersion': 1, 'components': [{'key': 'bench_365Bench', 'action': 'install'}]}))
            p.chmod(0o600)
            result = subprocess.run(['python3', str(ROOT / 'scripts/setup_selection.py'), 'benches', str(p)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'sysBenches/365Bench')


if __name__ == '__main__': unittest.main()
