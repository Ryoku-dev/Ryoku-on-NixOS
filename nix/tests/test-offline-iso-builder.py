#!/usr/bin/env python3
"""Test payload/archive assembly without downloading packages or producing an ISO."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BUILDER = Path(os.environ.get("RYOKU_OFFLINE_BUILDER_SOURCE", "nix/iso/offline/build.sh")).resolve()


class BuilderTest(unittest.TestCase):
    def run_builder(self, *args, fail=False, resume=False):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            bindir = work / "bin"
            bindir.mkdir()
            # These are command doubles only; no paths under /nix are created.
            nix = '''#!@PYTHON@
import json, os, pathlib, sys
args = sys.argv[1:]
with pathlib.Path(os.environ['TEST_CALLS']).open('a') as log:
    log.write(json.dumps(args) + '\\n')
if args[:2] == ['flake', 'archive']:
    print(json.dumps({'path': '/nix/store/root-source', 'inputs': {
        'one': {'path': '/nix/store/input-one', 'inputs': {
            'two': {'path': '/nix/store/input-two', 'inputs': {}}}}}}))
elif args[:1] == ['eval']:
    print('niri-latest-firefox-minimal-v2')
elif '--json' in args:
    if os.environ.get('FAIL_PAYLOAD'):
        sys.exit(7)
    print(json.dumps([{'drvPath': '/nix/store/payload.drv',
                      'outputs': {'out': '/nix/store/payload'}}]))
elif args[:2] == ['store', 'add-file']:
    import gzip
    exported = gzip.decompress(pathlib.Path(args[-1]).read_bytes()).decode()
    pathlib.Path(os.environ['TEST_EXPORTED']).write_text(exported)
    print('/nix/store/recipes.export.gz')
else:
    result = {name: json.loads(pathlib.Path(os.environ[var]).read_text()) for name, var in (
        ('paths', 'RYOKU_OFFLINE_STORE_PATHS'), ('sources', 'RYOKU_OFFLINE_SOURCE_PATHS'))}
    result['args'] = args
    result['derivations'] = os.environ['RYOKU_OFFLINE_DERIVATIONS']
    result['exported'] = pathlib.Path(os.environ['TEST_EXPORTED']).read_text()
    result['calls'] = [json.loads(line) for line in pathlib.Path(os.environ['TEST_CALLS']).read_text().splitlines()]
    pathlib.Path(os.environ['TEST_RESULT']).write_text(json.dumps(result))
'''
            (bindir / "nix").write_text(nix.replace('@PYTHON@', sys.executable))
            (bindir / "nix-store").write_text('''#!@PYTHON@
import sys
if sys.argv[1:] == ['--export', '--stdin']:
    sys.stdout.write(sys.stdin.read())
    sys.exit(0)
assert sys.argv[1:3] == ['--query', '--requisites']
assert '--include-outputs' not in sys.argv
if '/nix/store/payload.drv' in sys.argv:
    print('/nix/store/payload.drv\\n/nix/store/builder-source')
else:
    print('/nix/store/payload\\n/nix/store/build-tool')
'''.replace('@PYTHON@', sys.executable))
            for executable in bindir.iterdir():
                executable.chmod(0o755)
            env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}",
                       RYOKU_OFFLINE_FLAKE="path:/nix/store/test-source",
                       TEST_RESULT=str(work / "result.json"))
            env['TEST_EXPORTED'] = str(work / 'exported.txt')
            env['TMPDIR'] = str(work)
            env['TEST_CALLS'] = str(work / 'calls.jsonl')
            if resume:
                state = work / 'retained'
                state.mkdir()
                (state / '.ryoku-offline-preparation').touch()
                (state / 'profile').write_text('niri-latest-firefox-minimal-v2')
                (state / 'store-paths.json').write_text(json.dumps(['/nix/store/saved-output']))
                (state / 'sources.json').write_text(json.dumps(['/nix/store/saved-source']))
                (state / 'derivations-path').write_text('/nix/store/saved.export.gz')
                (state / 'payload-source').write_text('/nix/store/saved-source')
                (work / 'exported.txt').write_text('saved-export')
                args = (*args, '--resume', str(state))
            if fail:
                env["FAIL_PAYLOAD"] = "1"
            process = subprocess.run(["bash", "-euo", "pipefail", str(BUILDER), *args],
                                     cwd=work, env=env, capture_output=True, text=True)
            result = json.loads((work / "result.json").read_text()) if (work / "result.json").exists() else None
            return process, result

    def test_archive_keeps_transitive_sources_and_build_tools(self):
        process, result = self.run_builder("--out-link", "custom-result")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["sources"], ["/nix/store/input-one", "/nix/store/input-two", "/nix/store/root-source"])
        self.assertIn("/nix/store/build-tool", result["paths"])
        self.assertNotIn("/nix/store/payload.drv", result["paths"])
        self.assertEqual(result['exported'], '/nix/store/payload.drv\n')
        self.assertEqual(result['derivations'], '/nix/store/recipes.export.gz')
        self.assertIn("custom-result", result["args"])

    def test_generic_payload_can_omit_nvidia(self):
        process, result = self.run_builder("--no-nvidia")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIsNotNone(result)

    def test_failed_payload_never_assembles_image(self):
        process, result = self.run_builder(fail=True)
        self.assertNotEqual(process.returncode, 0)
        self.assertIsNone(result)

    def test_resume_skips_archive_payload_builds_and_export(self):
        process, result = self.run_builder(resume=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result['paths'], ['/nix/store/saved-output'])
        self.assertEqual(result['derivations'], '/nix/store/saved.export.gz')
        self.assertEqual(len(result['calls']), 1)
        self.assertIn('--expr', result['calls'][0])


if __name__ == "__main__":
    unittest.main()
