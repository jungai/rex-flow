"""Integration checks using real temporary Git repos and mocked Rex/agents."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('new-worktree.sh').resolve()


class NewWorktreeTests(unittest.TestCase):
    def test_launches_and_guards(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / 'repo'
            repo.mkdir()
            subprocess.run(['git', 'init', '-b', 'main', str(repo)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '--allow-empty', '-m', 'init'], check=True, capture_output=True)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            for agent in ['pi', 'opencode']:
                p = bin_dir / agent
                p.write_text('#!/bin/sh\nexit 0\n')
                p.chmod(0o755)
            rex = bin_dir / 'rex'
            rex.write_text('#!/usr/bin/env python3\nimport json, os, sys\nwith open(os.environ["REX_LOG"], "a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\nprint(json.dumps({"window_id":"window", "block_ids":["block"]}))\n')
            rex.chmod(0o755)
            log = root / 'rex.log'
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], REX_SESSION='test', REX_LOG=str(log), REX_FLOW_WORKTREE_ROOT=str(root / 'trees'))

            def run(slug, *args):
                return subprocess.run(['bash', str(SCRIPT), slug, *args, '--json'], cwd=repo, env=env, text=True, capture_output=True)

            task = '- fix "quotes"; $(touch nope)\nsecond line'
            for slug, flags, expected in [
                ('pi-default', ['--agent', 'pi'], ['pi', '--', task]),
                ('pi-model', ['--agent', 'pi', '--provider', 'example', '--model', 'model-id'], ['pi', '--provider', 'example', '--model', 'model-id', '--', task]),
                ('opencode', ['--agent', 'opencode', '--auto'], ['opencode', '--auto', '--prompt', task]),
            ]:
                result = run(slug, *flags, '--task', task)
                self.assertEqual(result.returncode, 0, result.stderr)
                data = json.loads(result.stdout)
                self.assertEqual(data['agent'], expected[0])
                self.assertEqual(data['task'], task)
                self.assertEqual(data['terminal_block_id'], 'block')
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                launch = calls[-2]
                self.assertEqual(launch[launch.index('--') + 1:], expected)
            for slug, flags in [
                ('bad-agent', ['--agent', 'unknown']),
                ('bad-auto', ['--agent', 'pi', '--auto']),
                ('bad-provider', ['--agent', 'pi', '--provider', 'example']),
                ('bad-model', ['--agent', 'opencode', '--model', 'example']),
            ]:
                result = run(slug, *flags, '--task', 'test')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / 'trees' / 'repo' / slug).exists())
            # Isolate marker tests from the real test runner's agent ancestry.
            ps = bin_dir / 'ps'
            ps.write_text('#!/bin/sh\ncase "$*" in *comm*) echo shell ;; *ppid*) echo 1 ;; esac\n')
            ps.chmod(0o755)
            # A Pi tool shell exposes these markers for automatic selection.
            env['AI_AGENT'] = 'pi'
            env['PI_CODING_AGENT'] = 'true'
            result = run('auto-pi', '--task', task)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['agent'], 'pi')
            env['AI_AGENT'] = 'opencode'
            result = run('auto-opencode', '--task', task)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['agent'], 'opencode')
            env.pop('AI_AGENT')
            env.pop('PI_CODING_AGENT')
            result = run('unknown-coordinator', '--task', task)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('cannot identify coordinator', result.stderr)
            self.assertFalse((root / 'trees' / 'repo' / 'unknown-coordinator').exists())
            before = log.read_text()
            result = run('shell', '--no-window')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('agent', json.loads(result.stdout))
            self.assertEqual(log.read_text(), before)
            result = run('pi-default', '--agent', 'pi', '--task', 'duplicate')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('already exists', result.stderr)


if __name__ == '__main__':
    unittest.main()
