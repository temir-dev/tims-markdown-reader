#!/usr/bin/env python3
"""Check source or release contents for private build paths and credential markers.

Values are never printed. This is a focused guard, not a comprehensive secret
scanner. Public copyright names and upstream license attribution are retained.
"""
import argparse
from pathlib import Path
import re

RULES = {
    'local home-directory path': rb'/(?:Users|home)/[^\s/\x00"\x27<>]+',
    'user-specific cache path': rb'/(?:private/)?var/folders/[A-Za-z0-9_/.-]+',
    # Provider-neutral: matches macOS's cloud-sync container folder and "<Provider>Drive-<account>" names.
    # Written so this file's own source does not match the rule.
    'cloud account path': rb'(?:Cloud(?:Storage)/|[A-Za-z]+Drive-)[^\s/\x00"\x27<>]+',
    'private key': rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
    'credential token': rb'(?:github_pat_[A-Za-z0-9_]{25,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}|sk_live_[A-Za-z0-9]{20,})',
}
PATTERNS = {label: re.compile(pattern) for label, pattern in RULES.items()}
PRIVATE_DIRECTORIES = {'private', 'research', 'build', 'dist', 'DerivedData', '.build', '.swiftpm', 'xcuserdata', '__pycache__'}
PRIVATE_SUFFIXES = {'.dmg', '.zip', '.tgz', '.p12', '.pfx', '.p8', '.pem', '.key', '.mobileprovision', '.provisionprofile', '.xcuserstate', '.log'}


def private_content(data):
    # Removing NUL bytes also exposes UTF-16 path strings in binary metadata.
    samples = [data, data.replace(b'\0', b'')] if b'\0' in data else [data]
    return [label for label, pattern in PATTERNS.items() if any(pattern.search(sample) for sample in samples)]


def has_content(directory):
    # Git cannot publish empty directories, including nested empty Xcode folders.
    return any(path.is_symlink() or not path.is_dir() or has_content(path)
               for path in directory.iterdir())


def scan_tree(root, source=False):
    root = Path(root).resolve(strict=True)
    findings = []
    files = 0

    def visit(directory):
        nonlocal files
        for path in sorted(directory.iterdir()):
            relative = path.relative_to(root).as_posix()
            if source and path.parent == root and path.name == '.git':
                # Git metadata is not source content; old history needs its own review.
                continue
            if path.is_symlink():
                applications_link = not source and path.parent == root and path.name == 'Applications' and path.readlink() == Path('/Applications')
                if not applications_link:
                    findings.append((relative, 'unexpected symlink'))
                continue
            if path.is_dir():
                if source and (path.name in PRIVATE_DIRECTORIES or path.name == '.git' or path.name.endswith('.dSYM')):
                    if has_content(path):
                        findings.append((relative, 'private/generated directory in source export'))
                else:
                    visit(path)
                continue
            if not path.is_file():
                findings.append((relative, 'unexpected nonregular file'))
                continue
            files += 1
            if path.name == '.DS_Store' or path.name.startswith('._'):
                findings.append((relative, 'Finder metadata'))
            if source and (path.suffix.lower() in PRIVATE_SUFFIXES or path.name == '.env' or path.name.startswith('.env.')):
                findings.append((relative, 'private/generated file in source export'))
            try:
                findings.extend((relative, label) for label in private_content(path.read_bytes()))
            except OSError as error:
                findings.append((relative, 'read failed: ' + type(error).__name__))

    visit(root)
    return files, findings


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--source', type=Path, metavar='DIRECTORY')
    mode.add_argument('--bundle', type=Path, metavar='APP_OR_MOUNT')
    args = parser.parse_args()
    count, findings = scan_tree(args.source or args.bundle, source=args.source is not None)
    for path, reason in findings:
        print(f'FAIL: {path}: {reason} (value withheld)')
    if findings:
        raise SystemExit(1)
    print(f'PASS: privacy checks on {count} files; no private-path or credential-marker matches')
