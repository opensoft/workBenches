#!/usr/bin/env python3
"""Validate the approved openBenches naming and dependent compatibility contracts."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
NAMING = ROOT / 'specs/033-rename-openbenches/contracts/naming-contract.md'
DEPENDENTS = ROOT / 'specs/033-rename-openbenches/contracts/dependent-inventory.md'

EXPECTED_ALIASES = [
    ['Repository/display', '`openBenches`', '`workBenches` remains in history and documented aliases'],
    ['Fresh checkout', '`~/Projects/openBenches`', 'Existing `workBenches` basenames remain discoverable'],
    ['Environment', '`OPENBENCHES_*`', '`WORKBENCHES_*` and established `WB_*` remain during the support window'],
    ['Setup command', '`setup-openbenches`', '`setup-workbenches`'],
    ['MCP command', '`openbenches-mcp-sync`', '`workbenches-mcp-sync`'],
    ['Credential command', '`openbenches-credential-sync`', '`workbenches-credential-sync`'],
    ['Installer flag', '`--openbenches`', '`--workbenches`'],
    ['Root flag', '`--openbenches-root`', '`--workbenches-root`'],
    ['Fresh config/cache/data roots', '`openbenches`', 'Existing `workbenches` roots remain in legacy-root mode'],
    ['QA runner label', '`openbenches-qa` after dual-label rollout', '`workbenches-qa` remains routable'],
    ['QA config', '`/etc/openbenches/release-qa.json`', '`/etc/workbenches/release-qa.json` fallback'],
]

EXPECTED_RESOLUTION_RULES = [
    'Explicit configured values take precedence in new/legacy/default order, except dangerous conflicting dual values fail.',
    'Equal old/new values are accepted. Different paths, endpoints, credential settings, or release configuration produce an actionable conflict.',
    'A root is selected per consumer contract; old and new trees are never merged.',
    'Only old root: legacy-root mode. Only new root: new-root mode.',
    'Both roots: use a documented explicit selection or refuse ambiguous stateful startup. Never duplicate profile inventories.',
    'Existing checkouts and runtime state are not moved automatically.',
    'Old and new producers/consumers must interoperate during the support window; consumer readers land before producer dual emission.',
    'One installed artifact has one implementation and one ownership lock. Command aliases do not create independent writers.',
]

EXPECTED_DURABLE_IDENTIFIERS = [
    'GHCR `ghcr.io/opensoft/workbenches-base` and `workbenches-dev-base`, schema-v1 image manifests, and existing OCI `io.workbenches.*` labels.',
    'Published tags, historical releases/assets/locks, old issue references, archived specs, and lane history.',
    'Existing named volumes, `.workbenches-history`, live container names, and persistent in-image paths.',
    'Schema-v1 `$id`/`kind` values, setup catalog keys, and credential payload fields.',
    'Keycloak realms/client IDs/audiences, Key Vault names and `workbenches-operation` tags, stored credential paths, and encrypted payloads.',
    'Installer lock/payload/journal names and exact historical wrapper fixtures during mixed-version operation.',
    'Generic `workbench` concepts, `workbench-base`, `devBenches`, `sysBenches`, `bioBenches`, openRepoShape compatibility tokens, Kubernetes annotations, and `xfactory-workbenches` service identities.',
]

EXPECTED_STATUSES = ['pending', 'in-progress', 'ready', 'landed', 'verified', 'blocked', 'not-required']

EXPECTED_DEPENDENCIES = [
    ['Current repository publisher', 'Exact `opensoft/workBenches` + `opensoft/openBenches` allowlist before cutover', 'Pre-rename'],
    ['Active release lines', 'Same publisher guard', 'Pre-rename'],
    ['openRepoProject', 'New/old checkout discovery; preserve root/marker/flag overrides; current docs after cutover', 'Consumer first'],
    ['openRepoKit', 'Accept either checkout basename; preserve existing root ABI; propagate component/spec/assembly pins in order', 'Consumer first'],
    ['new-workstation', 'New/old checkout and config discovery; preserve AI-Credentials boundary and recovery identity', 'Consumer first'],
    ['openProfiler', 'Native/WSL new-first/legacy-fallback manifest selection; no duplicate profiles; docs after cutover', 'Consumer first'],
    ['Install-Wave-Terminal', 'New/old checkout discovery and root aliases; preserve generated artifacts and caches', 'Consumer first'],
    ['pyBench', 'Config/lib/state mount compatibility and checkout CI slug update', 'Consumer first, then immediate slug sweep'],
    ['cloudBench', 'Config mount compatibility and checkout CI slug update', 'Consumer first, then immediate slug sweep'],
    ['openRepoTools', 'New-first/legacy lane-handoff environment reads; canonical/legacy repo aliases after cutover', 'Consumer first, then immediate slug sweep'],
    ['flutterBench', 'Checkout repository field only; preserve checker commit', 'Immediate slug sweep'],
    ['frappeBench', 'Checkout repository field only; preserve checker commit', 'Immediate slug sweep'],
    ['goBench', 'Checkout repository field only; preserve checker commit', 'Immediate slug sweep'],
    ['phpBench', 'Checkout repository field only; preserve checker commit', 'Immediate slug sweep'],
    ['Opensoft-Tenant / AI-Credentials', 'Owner-led provider/path compatibility review without exposing inventories or payloads', 'Before fresh roots'],
    ['openWorkBenchesCli', 'Update current extraction-source links after cutover; do not consolidate the family', 'Immediate slug sweep'],
    ['GitHub repository/settings', 'Controlled admin rename; description/topics/ruleset display; verify org rules and environments', 'Gated cutover'],
    ['Release/QA runners', 'Dual labels, environment aliases, config fallback; pause only at approved cutover window', 'Runtime compatibility'],
    ['openWorkBenches App/Service/assembly', 'No implementation dependency detected; document product boundary only', 'Not required'],
]


def section(document, heading):
    headings = list(re.finditer(rf'^#+ {re.escape(heading)}$', document, re.MULTILINE))
    if len(headings) != 1:
        raise AssertionError(f'Expected exactly one {heading!r} section')
    contents = document[headings[0].end():].lstrip('\n')
    next_heading = re.search(r'^#+ ', contents, re.MULTILINE)
    return (contents[:next_heading.start()] if next_heading else contents).strip('\n')


def markdown_table(contents):
    lines = [line for line in contents.splitlines() if line.startswith('|')]
    if len(lines) < 3:
        raise AssertionError('Expected a Markdown table with a header, separator, and data rows')
    rows = []
    for line in lines:
        if not line.endswith('|'):
            raise AssertionError(f'Malformed Markdown table row: {line!r}')
        rows.append([cell.strip() for cell in line[1:-1].split('|')])
    width = len(rows[0])
    if width == 0 or any(len(row) != width for row in rows):
        raise AssertionError('Every Markdown table row must have the same number of columns')
    if any(not re.fullmatch(r':?-{3,}:?', cell) for cell in rows[1]):
        raise AssertionError('Malformed Markdown table separator')
    return rows[0], rows[2:]


def numbered_rules(contents):
    rules = []
    for line in contents.splitlines():
        match = re.fullmatch(r'(\d+)\. (\S.*)', line)
        if not match:
            raise AssertionError(f'Malformed resolution rule: {line!r}')
        if int(match[1]) != len(rules) + 1:
            raise AssertionError('Resolution rules must be numbered consecutively')
        rules.append(match[2])
    return rules


def bullets(contents):
    lines = contents.split('\n\n', 1)[0].splitlines()
    if not lines or any(not line.startswith('- ') or len(line) == 2 for line in lines):
        raise AssertionError('Durable identifiers must be a non-empty bullet list')
    return [line[2:] for line in lines]


def status_vocabulary(contents):
    line = next((line for line in contents.splitlines() if line.startswith('Status values:')), None)
    if line is None:
        raise AssertionError('Dependent status vocabulary is missing')
    return re.findall(r'`([^`]+)`', line)


class NamingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document = NAMING.read_text()

    def test_required_canonical_and_legacy_aliases(self):
        header, rows = markdown_table(section(self.document, 'Canonical aliases'))
        self.assertEqual(header, ['Interface', 'Canonical', 'Legacy compatibility'])
        self.assertEqual(rows, EXPECTED_ALIASES)

    def test_sensitive_conflicts_no_merge_and_compatibility_rules(self):
        rules = numbered_rules(section(self.document, 'Resolution rules'))
        self.assertEqual(rules, EXPECTED_RESOLUTION_RULES)
        self.assertIn('Different paths, endpoints, credential settings, or release configuration', rules[1])
        self.assertIn('never merged', rules[2])
        self.assertIn('not moved automatically', rules[5])

    def test_durable_identifiers_and_non_targets_are_retained(self):
        values = bullets(section(self.document, 'Durable identifiers retained'))
        self.assertEqual(values, EXPECTED_DURABLE_IDENTIFIERS)
        self.assertIn(
            'New GHCR namespaces, legacy removal, credential rotation, and `openWorkBenches*` consolidation require separate proposals.',
            self.document)


class DependentInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document = DEPENDENTS.read_text()
        cls.contents = section(cls.document, 'Dependent inventory and landing order')
        cls.header, cls.rows = markdown_table(cls.contents)

    def test_status_vocabulary_is_exact(self):
        self.assertEqual(status_vocabulary(self.contents), EXPECTED_STATUSES)
        self.assertIn('Status values: `pending`, `in-progress`, `ready`, `landed`, `verified`, `blocked`, or `not-required`.',
                      self.contents)
        self.assertIn('do not duplicate implementation tasks owned by dependent repositories', self.contents)

    def test_required_dependency_rows_and_landing_order(self):
        self.assertEqual(self.header, ['Dependency', 'Required compatibility or slug change', 'Order', 'Status / evidence'])
        names = [row[0] for row in self.rows]
        self.assertEqual(len(names), len(set(names)), 'Dependency rows must be unique')
        actual = {row[0]: row for row in self.rows}
        for name, required_wording, order in EXPECTED_DEPENDENCIES:
            with self.subTest(dependency=name):
                row = actual.get(name)
                self.assertIsNotNone(row, f'Missing required dependency: {name}')
                self.assertIn(required_wording, row[1])
                self.assertEqual(row[2], order)

    def test_every_dependency_uses_a_declared_status(self):
        vocabulary = status_vocabulary(self.contents)
        self.assertTrue(self.rows, 'Dependent inventory must not be empty')
        for row in self.rows:
            with self.subTest(dependency=row[0]):
                match = re.match(r'^(`?)([a-z-]+)\1(?:\s|$)', row[3])
                self.assertIsNotNone(match, f'Malformed status/evidence cell: {row[3]!r}')
                self.assertIn(match[2], vocabulary)


if __name__ == '__main__':
    unittest.main()
