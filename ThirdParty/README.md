# Third-party code

The app bundles Swift Markdown 0.8.0, Swift cmark 0.8.0 and the official prebuilt Mermaid 11.16.1 runtime. Mermaid's JavaScript is byte-for-byte the file from the official npm package; nothing is installed or built from npm.

- `ThirdPartyNotices.txt` is the full license text shipped inside the app and the DMG.
- `Licenses/` holds the upstream license and NOTICE files, taken from the exact-version registry archives.
- `Mermaid.json` records where the Mermaid runtime came from and its hashes.
- `Inventory.json` lists the 72 packages embedded inside Mermaid, derived from its source maps rather than guessed from version ranges.

Run `python3 scripts/verify-notices.py` after any change. It checks the hashes and confirms every listed license appears in the shipped notices. It is a completeness check, not legal advice or a vulnerability scan; `scripts/check-advisories.py` looks up known advisories for the pinned versions.

To update Mermaid: verify the official archive, vendor the exact runtime file, rebuild the inventory from that version's source maps, collect the license files, regenerate the notices and hashes, update `ReaderAssets.mermaidVersion`, and rerun the WebKit tests. Don't just edit a checksum to make a failed check pass.

DOMPurify is used under its Apache-2.0 option. Khroma's MIT license comes from its license file, since its registry entry has no license field.

The app icon was generated for this project by the owner using OpenAI Codex.
