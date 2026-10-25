#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache"
swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/spm-cache" -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/cache"
APP="../ClipNest.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
BIN=$(swift build -c release -debug-info-format none --show-bin-path)
cp "$BIN/ClipNest" "$APP/Contents/MacOS/ClipNest"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClipNest</string>
<key>CFBundleIdentifier</key><string>local.clipnest.app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>ClipNest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built: ${APP:A}"
