#!/usr/bin/env python3
"""Read-only checks of the shipping bundle, using Apple's installed tools."""
import argparse
import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def verify(app, unsigned=False, distribution=False):
    app = app.resolve(strict=True)
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    with (ROOT / 'MarkdownReader/Info.plist').open('rb') as stream:
        source = plistlib.load(stream)
    for key in ('CFBundleShortVersionString', 'CFBundleVersion', 'LSMinimumSystemVersion', 'NSHumanReadableCopyright'):
        require(info[key] == source[key], 'Metadata mismatch: ' + key)
    require(info['LSMinimumSystemVersion'] == '14.0', 'Unexpected minimum OS')
    print(run(sys.executable, str(ROOT / 'scripts/check-privacy.py'), '--bundle', str(app)).strip())
    main = app / 'Contents/MacOS' / info['CFBundleExecutable']
    require(main.is_file(), 'Missing app executable')
    binaries = []
    magic = {b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
    for path in app.rglob('*'):
        if path.is_symlink():
            require(path.resolve().is_relative_to(app), 'Escaping bundle symlink: ' + str(path))
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            is_binary = stream.read(4) in magic
        if not is_binary:
            continue
        binaries.append(path)
        require(run('/usr/bin/lipo', '-archs', str(path)).strip() == 'arm64', 'Non-arm64 binary: ' + str(path))
        build = run('/usr/bin/xcrun', 'vtool', '-show-build', str(path))
        versions = re.findall(r'minos\s+(\d+(?:\.\d+){1,2})', build)
        require(versions and all(tuple(map(int, v.split('.'))) + (0,) * (3 - len(v.split('.'))) <= (14, 0, 0) for v in versions), 'Binary requires newer macOS: ' + str(path))
        require(re.search(r'platform\s+MACOS', build), 'Unexpected Mach-O platform')
        for line in run('/usr/bin/otool', '-L', str(path)).splitlines()[1:]:
            library = line.strip().split(' (compatibility')[0]
            # Fail closed if a future dependency adds non-system dynamic libraries.
            require(library.startswith(('/System/Library/', '/usr/lib/')), 'Non-system library needs explicit review: ' + library)
    require(binaries == [main], 'Executable layout changed; review nested signing before release')
    for original, bundled in [('LICENSE', 'LICENSE'), ('ThirdParty/ThirdPartyNotices.txt', 'ThirdPartyNotices.txt')]:
        require((ROOT / original).read_bytes() == (app / 'Contents/Resources' / bundled).read_bytes(), 'Missing or stale bundled license: ' + bundled)
    for asset in ('mermaid.min.js', 'mermaid-bootstrap.js', 'reader-find.js', 'reader.css'):
        resources = list(app.rglob(asset))
        require(len(resources) == 1 and resources[0].read_bytes() == (ROOT / 'ReaderCore/Sources/ReaderCore/Resources' / asset).read_bytes(), 'Missing or stale reader asset: ' + asset)
    if not unsigned:
        print(run('/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)).strip())
        signature = run('/usr/bin/codesign', '-d', '--verbose=4', str(app))
        require('runtime' in signature, 'Hardened Runtime is missing')
        raw = subprocess.check_output(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL)
        entitlements = plistlib.loads(raw) if raw.strip() else {}
        require(not entitlements.get('com.apple.security.get-task-allow'), 'Debug entitlement in release')
        require(not any(entitlements.get(k) for k in ('com.apple.security.cs.disable-library-validation', 'com.apple.security.cs.allow-unsigned-executable-memory', 'com.apple.security.cs.disable-executable-page-protection')), 'Unexpected runtime exception')
        if distribution:
            require('Authority=Developer ID Application:' in signature and 'Timestamp=' in signature, 'Missing Developer ID identity or secure timestamp')
            print(run('/usr/bin/xcrun', 'stapler', 'validate', str(app)).strip())
            print(run('/usr/bin/syspolicy_check', 'distribution', str(app)).strip())
    print('PASS: arm64, macOS 14 compatibility metadata, system libraries, bundle resources' + (', signature and runtime' if not unsigned else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--unsigned', action='store_true')
    modes.add_argument('--distribution', action='store_true')
    args = parser.parse_args()
    verify(args.app, args.unsigned, args.distribution)
