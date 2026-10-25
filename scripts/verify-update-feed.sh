#!/bin/zsh
# Read-only network regression: real Sparkle headers, parsing and public-key validation.
set -eu
cd "${0:A:h}/.."
app="$PWD/.build/FeedProbe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
ditto ../ClipNest.app/Contents/Frameworks/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp ../ClipNest.app/Contents/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.clipnest.feedprobe' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable FeedProbe' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 0' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :SUEnableAutomaticChecks false' "$app/Contents/Info.plist"
clang -fobjc-arc -framework Cocoa -framework Sparkle -F "$app/Contents/Frameworks" -Wl,-rpath,@executable_path/../Frameworks scripts/verify-update-feed.m -o "$app/Contents/MacOS/FeedProbe"
codesign --force --sign - "$app" >/dev/null
base=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' ../ClipNest.app/Contents/Info.plist)
"$app/Contents/MacOS/FeedProbe" "${1:-$base?clipnest_check=$(uuidgen)}"
