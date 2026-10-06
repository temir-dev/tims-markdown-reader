"""Finder only offers the app for Markdown files if Info.plist claims them in every way macOS matches."""
from pathlib import Path
import plistlib
import unittest

with (Path(__file__).resolve().parents[2] / 'MarkdownReader/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)


class DocumentTypes(unittest.TestCase):
    def claimed(self, key):
        return {value for entry in info['CFBundleDocumentTypes'] for value in entry.get(key, [])}

    def test_markdown_is_claimed_by_type_and_by_extension(self):
        # Other apps redefine .md as their own type; the extension claim still matches then.
        self.assertIn('net.daringfireball.markdown', self.claimed('LSItemContentTypes'))
        self.assertEqual(self.claimed('CFBundleTypeExtensions'), {'md', 'markdown', 'mdx'})

    def test_extension_claims_are_not_mixed_with_type_claims(self):
        # macOS ignores CFBundleTypeExtensions in an entry that also has LSItemContentTypes.
        for entry in info['CFBundleDocumentTypes']:
            self.assertFalse('LSItemContentTypes' in entry and 'CFBundleTypeExtensions' in entry)

    def test_every_entry_is_a_read_only_default_handler(self):
        for entry in info['CFBundleDocumentTypes']:
            self.assertEqual((entry['CFBundleTypeRole'], entry['LSHandlerRank']), ('Viewer', 'Default'))

    def test_markdown_type_is_declared_for_macs_where_nothing_else_declares_it(self):
        declared = {entry['UTTypeIdentifier']: entry for entry in info['UTImportedTypeDeclarations']}
        markdown = declared['net.daringfireball.markdown']
        self.assertEqual(markdown['UTTypeConformsTo'], ['public.plain-text'])
        self.assertEqual(markdown['UTTypeTagSpecification']['public.filename-extension'], ['md', 'markdown'])
        # Only an app that invented a type may export it.
        self.assertNotIn('UTExportedTypeDeclarations', info)


if __name__ == '__main__':
    unittest.main()
