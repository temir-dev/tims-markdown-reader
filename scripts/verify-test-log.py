#!/usr/bin/env python3
"""Reject incomplete Swift Testing runs, even when the runner exits with status zero."""
import re
import sys
from pathlib import Path


def completed_test_count(log):
    # XCTest prints a successful zero-test summary before Swift Testing starts.
    # Only accept Swift Testing's final, nonempty run summary. A changed output
    # format fails closed and requires this small check to be updated.
    lines = log.rstrip().splitlines()
    if not lines:
        return None
    # A preceding successful run must not hide a later interrupted run.
    match = re.fullmatch(
        r'✔ Test run with ([1-9][0-9]*) tests? in [0-9]+ suites? passed after .+\.',
        lines[-1],
    )
    return int(match[1]) if match else None


if __name__ == '__main__':
    path = Path(sys.argv[1])
    count = completed_test_count(path.read_text())
    if count is None:
        raise SystemExit('Incomplete or unsuccessful Swift Testing run; inspect ' + str(path))
    print(f'Verified complete run: {count} tests ({path.name})')
