import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('privacy', Path(__file__).resolve().parents[2] / 'scripts/check-privacy.py')
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PrivacyChecks(unittest.TestCase):
    def test_home_and_cloud_paths_in_binary_data(self):
        home = b'/' + b'Users' + b'/sample/project/app.swift'
        cloud = b'Example' + b'Drive-' + b'sample@example.invalid-folder/project'
        container = b'Library/Cloud' + b'Storage/' + b'Provider-sample@example.invalid/project'
        self.assertIn('local home-directory path', privacy.private_content(b'\0' + home + b'\0'))
        self.assertIn('cloud account path', privacy.private_content(cloud))
        self.assertIn('cloud account path', privacy.private_content(container))
        self.assertIn('local home-directory path', privacy.private_content(home.decode().encode('utf-16-le')))

    def test_private_cache_paths(self):
        path = b'/private/' + b'var/folders/' + b'xx/sample/T/build'
        self.assertIn('user-specific cache path', privacy.private_content(path))

    def test_private_keys_and_tokens(self):
        key = b'-----BEGIN ' + b'PRIVATE KEY-----'
        token = b'gh' + b'p_' + b'A' * 36
        self.assertIn('private key', privacy.private_content(key))
        self.assertIn('credential token', privacy.private_content(token))

    def test_public_credit_and_license_email_are_allowed(self):
        self.assertEqual(privacy.private_content(b'Copyright 2026 Tim Tairov\nauthor@example.com\n/System/Library/Frameworks'), [])

    def test_private_directories_and_exports_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'build').mkdir()
            (root / 'build' / 'cache').write_bytes(b'generated')
            (root / '.env').write_text('placeholder')
            (root / '.DS_Store').write_bytes(b'metadata')
            _, findings = privacy.scan_tree(root, source=True)
            self.assertEqual({path for path, _ in findings}, {'build', '.env', '.DS_Store'})

    def test_only_dmg_applications_link_is_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'Applications').symlink_to('/Applications')
            self.assertEqual(privacy.scan_tree(root)[1], [])
            self.assertTrue(privacy.scan_tree(root, source=True)[1])
            (root / 'outside').symlink_to('/tmp')
            self.assertTrue(privacy.scan_tree(root)[1])

    def test_empty_generated_directory_has_no_publishable_content(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / '.swiftpm' / 'xcode').mkdir(parents=True)
            self.assertEqual(privacy.scan_tree(root, source=True)[1], [])
            (root / '.swiftpm' / 'workspace').write_bytes(b'generated')
            self.assertTrue(privacy.scan_tree(root, source=True)[1])
