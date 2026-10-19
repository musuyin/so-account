from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from build_android import build, dependency_failure


class BuildTest(unittest.TestCase):
    def test_recognizes_dependency_resolution_but_not_compilation_failures(self):
        self.assertTrue(dependency_failure("could not resolve plugin artifact 'com.android.application'"))
        self.assertTrue(dependency_failure('Could not GET https://dl.google.com/file'))
        self.assertFalse(dependency_failure('Compilation failed: unresolved reference'))
        self.assertFalse(dependency_failure('Could not GET file\nExecution failed for task :app:compileKotlin'))
        self.assertFalse(dependency_failure('Error: missing Dart symbol'))

    def test_retries_only_dependency_failure_and_keeps_attempt_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            def run(command, **kwargs):
                calls.append(command)
                kwargs['stdout'].write('could not resolve plugin artifact' if len(calls) == 1 else 'Built APK')
                return SimpleNamespace(returncode=1 if len(calls) == 1 else 0)
            self.assertEqual(build(['flutter'], directory, run=run, pause=lambda _: None), 0)
            self.assertEqual(len(calls), 2)
            self.assertIn('resolve plugin', (Path(directory) / 'android-build-1.log').read_text())

    def test_persistent_network_failure_stops_at_three_attempts(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            def run(command, **kwargs):
                calls.append(command)
                kwargs['stdout'].write('Read timed out')
                return SimpleNamespace(returncode=1)
            self.assertEqual(build(['flutter'], directory, run=run, pause=lambda _: None), 1)
            self.assertEqual(len(calls), 3)

    def test_compilation_failure_is_not_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            def run(command, **kwargs):
                calls.append(command)
                kwargs['stdout'].write('Compilation failed')
                return SimpleNamespace(returncode=1)
            self.assertEqual(build(['flutter'], directory, run=run, pause=lambda _: None), 1)
            self.assertEqual(len(calls), 1)
