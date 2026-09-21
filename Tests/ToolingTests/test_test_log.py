"""The release checks must not accept an empty or interrupted test run."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('test_log', Path(__file__).resolve().parents[2] / 'scripts/verify-test-log.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TestCompletionChecks(unittest.TestCase):
    def test_complete_run(self):
        self.assertEqual(module.completed_test_count('✔ Test run with 41 tests in 0 suites passed after 0.014 seconds.\n'), 41)

    def test_xctest_zero_tests_is_not_success(self):
        self.assertIsNone(module.completed_test_count("Test Suite 'All tests' passed.\nExecuted 0 tests, with 0 failures\n"))

    def test_individual_passes_are_not_a_complete_run(self):
        partial = '✔ Test readingSettings() passed after 1.0 seconds.\n'
        earlier_success = '✔ Test run with 38 tests in 0 suites passed after 0.014 seconds.\n'
        for log in [partial, earlier_success + '◇ Test run started.\n' + partial]:
            with self.subTest(log=log):
                self.assertIsNone(module.completed_test_count(log))

    def test_failed_run(self):
        self.assertIsNone(module.completed_test_count('✘ Test run with 41 tests in 0 suites failed after 0.014 seconds with 1 issue.\n'))

    def test_empty_run(self):
        self.assertIsNone(module.completed_test_count('✔ Test run with 0 tests in 0 suites passed after 0.014 seconds.\n'))
