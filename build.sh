#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache"
swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/spm-cache" -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/cache"
APP="../ClipNest.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
install -m 644 ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
BIN=$(swift build -c release -debug-info-format none --show-bin-path)
cp "$BIN/ClipNest" "$APP/Contents/MacOS/ClipNest"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClipNest</string>
<key>CFBundleIdentifier</key><string>local.clipnest.app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>ClipNest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.4</string>
<key>CFBundleVersion</key><string>17</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/hieupnvmg/ClipNest/main/updates/appcast.xml</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST
plutil -insert SUPublicEDKey -string "$(cat Assets/UpdatePublicKey.txt)" "$APP/Contents/Info.plist"
# Preserve Sparkle's original signatures on its framework and helper executables.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: ${APP:A}"
