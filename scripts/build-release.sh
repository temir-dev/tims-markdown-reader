#!/bin/zsh
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
project_root=${0:A:h:h}
mode=${1:---local}
if (( $# > 1 )) || [[ "$mode" != --local && "$mode" != --notarize ]]; then
  print -u2 'Usage: scripts/build-release.sh [--local|--notarize]'; exit 2
fi
# Public mode fails before building if credentials are missing.
if [[ "$mode" == --notarize ]]; then
  : "${READER_SIGN_IDENTITY:?Set READER_SIGN_IDENTITY to your Developer ID Application identity}"
  : "${READER_NOTARY_PROFILE:?Set READER_NOTARY_PROFILE to a saved notarytool Keychain profile}"
  [[ "$READER_SIGN_IDENTITY" == 'Developer ID Application: '* ]] || { print -u2 'Developer ID Application identity required.'; exit 1; }
  security find-identity -v -p codesigning | /usr/bin/grep -F -- "\"$READER_SIGN_IDENTITY\"" >/dev/null || { print -u2 'Signing identity unavailable.'; exit 1; }
fi
python3 "$project_root/scripts/check-privacy.py" --source "$project_root"
python3 "$project_root/scripts/verify-notices.py"
# Avoid cloud-sync metadata in generated signed bundles. Preserve build evidence.
build_root=${READER_BUILD_ROOT:-$(mktemp -d "/private/tmp/markdown-reader-release.XXXXXX")}
build_root=${build_root:A}
[[ "$build_root/" != "$project_root/"* ]] || { print -u2 'READER_BUILD_ROOT must be outside the source folder.'; exit 1; }
release_dir=${READER_RELEASE_DIR:-"$build_root/releases"}
release_dir=${release_dir:A}
[[ "$release_dir/" != "$project_root/"* ]] || { print -u2 'READER_RELEASE_DIR must be outside the source folder.'; exit 1; }
mkdir -p "$build_root" "$release_dir"
export CLANG_MODULE_CACHE_PATH="$build_root/ModuleCache"
product_name="Tim's Markdown Reader"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/MarkdownReader/Info.plist")
app="$build_root/ReleaseDerivedData/Build/Products/Release/$product_name.app"
release_name="$product_name $version arm64"
[[ "$mode" != --local ]] || release_name+=' local-preview'
print "Build workspace: $build_root"
xcodebuild -project "$project_root/MarkdownReader.xcodeproj" \
  -scheme "$product_name" -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_root/ReleaseDerivedData" -clonedSourcePackagesDirPath "$build_root/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=YES build
# Preserve private dSYM evidence, but remove local source paths from the shipping
# executable's debug symbol table before any signing or notarization.
xcrun strip -S "$app/Contents/MacOS/$product_name"
python3 "$project_root/scripts/verify-release.py" "$app" --unsigned
if [[ "$mode" == --notarize ]]; then
  codesign --force --sign "$READER_SIGN_IDENTITY" --options runtime --timestamp "$app"
  ditto -c -k --keepParent "$app" "$build_root/notary-app.zip"
  xcrun notarytool submit "$build_root/notary-app.zip" --keychain-profile "$READER_NOTARY_PROFILE" --wait --output-format json > "$build_root/app-notarization.json"
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r.get("status") == "Accepted", r' "$build_root/app-notarization.json"
  xcrun stapler staple "$app"
  python3 "$project_root/scripts/verify-release.py" "$app" --distribution
else
  codesign --force --sign - --options runtime --timestamp=none "$app"
  python3 "$project_root/scripts/verify-release.py" "$app"
fi
# Recent macOS deprecates hdiutil's create/attach/detach verbs in favour of
# `diskutil image`. Older systems, including CI runners, only have hdiutil.
if diskutil image --help >/dev/null 2>&1; then modern_images=1; else modern_images=0; fi
create_image() {  # volume name, source folder, output image
  if (( modern_images )); then diskutil image create from --format UDZO --volumeName "$1" "$2" "$3"
  else hdiutil create -volname "$1" -srcfolder "$2" -format UDZO "$3"; fi
}
attach_image() {  # image, mount point
  if (( modern_images )); then diskutil image attach --readOnly --nobrowse --mountPoint "$2" "$1"
  else hdiutil attach -readonly -nobrowse -mountpoint "$2" "$1"; fi
}
detach_image() {  # mount point
  if (( modern_images )); then diskutil eject "$1"; else hdiutil detach "$1"; fi
}
stage=$(mktemp -d "$build_root/dmg-stage.XXXXXX")
mount_point=""
mounted=0
cleanup() {
  if (( mounted )); then detach_image "$mount_point" >/dev/null 2>&1 || true; fi
  [[ -z "$mount_point" ]] || rmdir "$mount_point" 2>/dev/null || true
  rm -rf -- "$stage"
}
trap cleanup EXIT
ditto "$app" "$stage/$product_name.app"
ln -s /Applications "$stage/Applications"
cp "$project_root/LICENSE" "$stage/LICENSE.txt"
cp "$project_root/ThirdParty/ThirdPartyNotices.txt" "$stage/ThirdPartyNotices.txt"
cp "$project_root/PRIVACY.md" "$stage/Privacy.txt"
cat > "$stage/Install.txt" <<'INSTALL'
Tim’s Markdown Reader

Requires an Apple silicon Mac (M1 or later) running macOS 14 or later.
Intel Macs are not supported.
Drag the app to Applications, eject this disk image, then open the app.
No Xcode, Homebrew, account, or internet connection is needed for reading.

To use it for double-clicking Markdown files: Finder → Get Info → Open with →
Tim’s Markdown Reader → Change All. Repeat for .markdown or .mdx as needed.

Updates are manual: the app menu's Check for Updates… opens the download page.
Quit the app and replace it with the newer download.
To uninstall, quit the app and move it from Applications to Trash.
Your documents are not removed. Reading does not modify the source files.

Free and open source, under the MIT License. Provided as is, without warranty.
Full license and dependency notices are included here and in the Licenses menu.
Reading is offline; clicked web links open your browser.
INSTALL
if [[ "$mode" == --local ]]; then
  cat >> "$stage/Install.txt" <<'INSTALL'

LOCAL PREVIEW: ad-hoc signed, not notarized by Apple. This is not the public
release. macOS may block it. Where permitted, after attempting to open it,
System Settings → Privacy & Security → Open Anyway can allow this app.
Never disable Gatekeeper globally.
INSTALL
else
  print '\nThis release is Developer ID signed and Apple notarized. A normal first-open\nconfirmation may still appear.' >> "$stage/Install.txt"
fi
staged_dmg="$build_root/$release_name.dmg"
[[ ! -e "$staged_dmg" ]] || { print -u2 'Output exists; use a fresh READER_BUILD_ROOT.'; exit 1; }
create_image "$product_name" "$stage" "$staged_dmg"
if [[ "$mode" == --notarize ]]; then
  codesign --sign "$READER_SIGN_IDENTITY" --timestamp "$staged_dmg"
  xcrun notarytool submit "$staged_dmg" --keychain-profile "$READER_NOTARY_PROFILE" --wait --output-format json > "$build_root/dmg-notarization.json"
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r.get("status") == "Accepted", r' "$build_root/dmg-notarization.json"
  xcrun stapler staple "$staged_dmg"
  xcrun stapler validate "$staged_dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$staged_dmg"
fi
hdiutil verify "$staged_dmg"
# Inspect the actual packaged bytes, including everything outside the app bundle.
mount_point=$(mktemp -d "$build_root/dmg-check.XXXXXX")
attach_image "$staged_dmg" "$mount_point" > "$build_root/dmg-mount.log"
mounted=1
python3 "$project_root/scripts/check-privacy.py" --bundle "$mount_point"
python3 "$project_root/scripts/verify-release.py" "$mount_point/$product_name.app"
detach_image "$mount_point"
mounted=0
rmdir "$mount_point"
mount_point=""
release="$release_dir/$release_name.dmg"
if [[ -e "$release" || -e "$release.sha256" ]]; then
  mkdir -p "$release_dir/archive"
  previous=$(mktemp -d "$release_dir/archive/previous.XXXXXX")
  for old in "$release" "$release.sha256"; do
    [[ ! -e "$old" ]] || mv "$old" "$previous/"
  done
fi
cp "$staged_dmg" "$release"
(cd "$release_dir" && shasum -a 256 "$release_name.dmg" > "$release_name.dmg.sha256" && shasum -a 256 -c "$release_name.dmg.sha256")
print "Built: $release"
print "Preserved build, app, symbols and any notarization receipts: $build_root"
[[ "$mode" != --local ]] || print 'LOCAL PREVIEW ONLY — not a notarized public release.'
