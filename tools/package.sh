#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release --product WaltzAssistant
task_bin_dir=$(swift build --build-system native -c release --show-bin-path)
task_output="$PWD/dist"
task_stage=$(mktemp -d /tmp/waltz-package.XXXXXX)
task_app="$task_stage/舞会助手.app"
mkdir -p "$task_output"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin_dir/WaltzAssistant" "$task_app/Contents/MacOS/WaltzAssistant"
cp Sources/WaltzCore/Resources/guide.json "$task_app/Contents/Resources/guide.json"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.th.waltzassistant</string>
<key>CFBundleName</key><string>舞会助手</string>
<key>CFBundleDisplayName</key><string>舞会助手</string>
<key>CFBundleExecutable</key><string>WaltzAssistant</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.6</string>
<key>CFBundleVersion</key><string>17</string>
<key>CFBundleIconFile</key><string>WaltzIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>只读取所选游戏客户端或 iPhone 镜像窗口，在本机识别当前游戏人物、爱心、菜单和问答。不上传画面。</string>
</dict></plist>
PLIST
task_icon_dir=$(mktemp -d)/Waltz.iconset
swift tools/make-icon.swift "$task_icon_dir"
iconutil -c icns "$task_icon_dir" -o "$task_app/Contents/Resources/WaltzIcon.icns"
# Clear only Finder/resource-fork metadata on our generated output before signing.
xattr -dr com.apple.FinderInfo "$task_app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$task_app" 2>/dev/null || true
codesign --force --deep --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
plutil -lint "$task_app/Contents/Info.plist"
ditto -c -k --keepParent "$task_app" "$task_output/舞会助手-v1.3.6-mac-arm64.zip"
printf '%s\n' "$task_app"
