#!/usr/bin/env python3
"""Catalog coverage, evidence qualification and safe deterministic compilation."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('catalog', ROOT / 'scripts/setup-tool-catalog.py')
catalog = importlib.util.module_from_spec(spec); spec.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(catalog.CATALOG.read_text())
        self.entries = {e['id']: e for e in self.data['entries']}

    def test_supplied_terminal_inventory_and_product_boundaries_are_retained(self):
        expected = '''claude_cli codex_cli gemini_cli antigravity_cli jules_tools grok_build muse_code kiro_cli copilot_cli bob_shell devin_cli pool_cli qwen_cli kimi_code kimi_legacy zcode_cli codebuddy_cli trae_agent mimo_code qoder_cn_cli qoder_cli iflow_cli neovate_code vibe_cli opencode_cli crush_cli aider_cli pi_cli goose_cli cline_cli continue_cli kilo_cli roo_cli plandex_cli codebuff_cli forgecode_cli gptme_cli letta_code nanocoder_cli kode_cli codewhale_cli jcode_cli reasonix_cli oh_my_pi cursor_cli amp_cli droid_cli auggie_cli junie_cli tabnine_cli mentat_cli ante_cli thegitai_cli openhands_cli swe_agent mini_swe_agent autocoderover devon_cli ra_aid deep_agents_code pydantic_deep_agents tau_cli dexto_cli atomic_agent bitfun_cli maki_cli vt_code hax_cli agentty_cli cecli every_code open_codex nori_cli hermes_agent prime_agent open_interpreter'''.split()
        actual = {e['id'] for e in self.data['entries'] if e['category'] == 'tui'}
        self.assertEqual(actual, set(expected) | {'dsh_cli'})
        self.assertEqual(len(actual), 77)
        for key in ('codex_gui', 'codex_cli', 'codex_vscode', 'kimi_code', 'kimi_legacy', 'qoder_cn_cli', 'qoder_cli', 'vscode', 'cursor_ide', 'cursor_cli', 'herder'):
            self.assertIn(key, self.entries)
        self.assertEqual(self.entries['qwen_cli']['cliGroup'], 'model_china')
        self.assertEqual(self.entries['qwen_cli']['modelPolicy'], 'selectable-providers')
        self.assertNotEqual(self.entries['qoder_cn_cli']['developer'], self.entries['qoder_cli']['developer'])
        self.assertEqual(self.entries['kimi_legacy']['productStatus'], 'transitioning')
        self.assertFalse(self.entries['kimi_legacy']['detection']['commands'])
        self.assertEqual(self.entries['kimi_code']['detection']['npmPackage'], '@moonshot-ai/kimi-code')
        self.assertEqual(self.entries['jules_tools']['executionLocation'], 'remote')
        self.assertEqual(self.entries['codex_gui']['category'], 'gui')
        self.assertEqual(self.entries['codex_vscode']['category'], 'extensions')
        self.assertEqual(self.entries['vscode']['category'], 'editors')
        self.assertIn('agent workspace', self.entries['herder']['tags'])

    def test_claims_are_qualified_and_interoperability_is_not_an_interface_category(self):
        catalog.validate(self.data)
        for e in self.data['entries']:
            self.assertTrue(e['verification']['note'])
            self.assertIn(e['verification']['basis'], ('user-provided', 'existing-catalog', 'primary-source'))
            text = catalog.about(e)
            for field in ('Developer relationship:', 'Developer region:', 'Model policy:', 'Terminal modes:', 'Execution location:',
                          'Product status:', 'Lineage:', 'Additional surfaces:', 'Interactive interface:', 'Noninteractive execution:',
                          'Scriptable input/output:', 'Autonomy:', 'Permissions:', 'Invokes another agent:', 'Can be invoked externally:',
                          'Delegation model:', 'State exchange:', 'Parallel execution:'):
                self.assertIn(field, text)
            if not e['managed']:
                self.assertIn('Manual setup:', text)
                self.assertIn('Presence does not establish login', text)
        for section in self.data['categories'].values():
            self.assertFalse(any('interoperability' in r['label'].lower() for r in section))
        self.assertEqual(self.entries['iflow_cli']['developerRelationship'], 'unverified')
        self.assertIn('Not yet verified', self.entries['grok_build']['interoperability']['stateExchange'])
        for key in ('codex_cli', 'claude_cli', 'opencode_cli'):
            e = self.entries[key]
            self.assertTrue(e['verification']['capabilityEvidence'])
            self.assertIn('Available:', e['capabilities']['noninteractive'])
            self.assertIn('does not imply', e['interoperability']['invokesAgents'])
            self.assertIn('not yet verified', e['interoperability']['stateExchange'])

    def test_runtime_snapshots_match_canonical_data_and_preserve_old_reference_indexes(self):
        shell, python = catalog.snapshots(catalog.validate(self.data))
        self.assertEqual(catalog.BASH.read_text(), shell)
        self.assertEqual(catalog.PYTHON.read_text(), python)
        result = subprocess.run(['bash', '-c', 'source "$1"; printf "%s\\n" "${setup_catalog_harness_refs[*]:0:9}" "${setup_catalog_tool_refs[*]:0:4}" "${setup_harness_members[tui]}"', 'bash', str(catalog.BASH)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0].split(), self.data['legacyReferenceOrder']['harness'])
        self.assertEqual(lines[1].split(), self.data['legacyReferenceOrder']['tool'])
        self.assertEqual(lines[2].split()[:6], ['claude_cli', 'copilot_cli', 'codex_cli', 'antigravity_cli', 'opencode_cli', 'pi_cli'])
        self.assertEqual(len(lines[2].split()), 77)

    def test_invalid_ids_controls_commands_sources_and_managed_keys_are_rejected(self):
        mutations = [lambda d: d['entries'].append(copy.deepcopy(d['entries'][0])),
                     lambda d: d['entries'][0].update(id='bad key'),
                     lambda d: d['entries'][0].update(label='bad\x1b[2J'),
                     lambda d: d['entries'][0].update(about='host /home/someone/project'),
                     lambda d: d['entries'][0]['detection'].update(commands=['sh -c do-something']),
                     lambda d: d['entries'][0]['verification'].update(evidence=['javascript:bad']),
                     lambda d: d['entries'][0].update(cliGroup='unknown'),
                     lambda d: d['entries'][0].update(managed=False)]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                data = copy.deepcopy(self.data); mutate(data)
                with self.assertRaises(ValueError): catalog.validate(data)

    def test_shell_metadata_is_literal_even_with_substitutions_quotes_and_newlines(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); sentinel = directory / 'executed'
            text = f"quoted '$(touch {sentinel})' `touch {sentinel}` $HOME\nsecond line"
            self.data['entries'][0]['about'] = text
            shell, _ = catalog.snapshots(catalog.validate(self.data))
            snapshot = directory / 'data.sh'; snapshot.write_text(shell)
            result = subprocess.run(['bash', '-c', 'source "$1"; printf "%s" "${component_about[claude_cli]}"', 'bash', str(snapshot)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(result.stdout.startswith(text))
            self.assertFalse(sentinel.exists())


if __name__ == '__main__': unittest.main()
