#!/bin/zsh
# Build a DMG and publishable signed update feed. Private key stays in Keychain.
set -eu
cd "${0:A:h}"
./build.sh
release_dir="${1:-..}"
release_dir="${release_dir:A}"
mkdir -p "$release_dir" updates
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ../ClipNest.app/Contents/Info.plist)
archive="ClipNest-${version}-Apple-Silicon.dmg"
staging=$(mktemp -d "$PWD/.build/release.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/dmg" "$staging/updates"
ditto ../ClipNest.app "$staging/dmg/ClipNest.app"
ln -s /Applications "$staging/dmg/Applications"
hdiutil create -volname ClipNest -srcfolder "$staging/dmg" -ov -format UDZO "$release_dir/$archive"
hdiutil verify "$release_dir/$archive"
cp "$release_dir/$archive" "$staging/updates/$archive"
if [[ -f "updates/$version.md" ]]; then
  cp "updates/$version.md" "$staging/updates/${archive:r}.md"
fi
tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
"$tools/generate_appcast" --account ClipNest-updates --download-url-prefix "https://github.com/hieupnvmg/ClipNest/releases/download/v$version/" --link https://github.com/hieupnvmg/ClipNest --embed-release-notes --maximum-deltas 0 -o "$PWD/updates/appcast.xml" "$staging/updates"
"$tools/sign_update" --account ClipNest-updates --verify "$PWD/updates/appcast.xml"
signature=$(python3 - "$PWD/updates/appcast.xml" "$archive" "$release_dir/$archive" <<'PY'
import pathlib,sys,xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
enclosure = next(e for e in root.findall('./channel/item/enclosure') if e.attrib['url'].endswith('/'+sys.argv[2]))
assert int(enclosure.attrib['length']) == pathlib.Path(sys.argv[3]).stat().st_size, 'Feed size does not match update archive'
print(enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
PY
)
"$tools/sign_update" --account ClipNest-updates --verify "$release_dir/$archive" "$signature"
ditto -c -k --sequesterRsrc --keepParent ../ClipNest.app "$release_dir/ClipNest-${version}-Apple-Silicon.zip"
echo "Signed release ready: $release_dir/$archive"
echo "Upload the DMG to GitHub Releases, then publish updates/appcast.xml on main."
