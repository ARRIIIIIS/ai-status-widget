#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$DIR/AIStatusWidget.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES" /tmp/swift-module-cache /tmp/AppIcon.iconset

# 1. Generate 1024x1024 Liquid Glass dual-arc icon -> AppIcon.icns
swift -module-cache-path /tmp/swift-module-cache "$DIR/make_icon.swift" /tmp/AppIcon_1024.png
for sz in 32 64 128 256 512 1024; do
    sips -z $sz $sz /tmp/AppIcon_1024.png --out "/tmp/AppIcon.iconset/p_${sz}.png" >/dev/null
done
/usr/bin/python3 - "$RESOURCES/AppIcon.icns" << 'PYEOF'
import struct, sys
from pathlib import Path

mapping = [
    (b"ic11", "/tmp/AppIcon.iconset/p_32.png"),
    (b"ic12", "/tmp/AppIcon.iconset/p_64.png"),
    (b"ic07", "/tmp/AppIcon.iconset/p_128.png"),
    (b"ic13", "/tmp/AppIcon.iconset/p_256.png"),
    (b"ic08", "/tmp/AppIcon.iconset/p_256.png"),
    (b"ic14", "/tmp/AppIcon.iconset/p_512.png"),
    (b"ic09", "/tmp/AppIcon.iconset/p_512.png"),
    (b"ic10", "/tmp/AppIcon.iconset/p_1024.png"),
]
chunks = bytearray()
for ostype, path in mapping:
    data = Path(path).read_bytes()
    chunks += ostype + struct.pack(">I", len(data) + 8) + data
header = b"icns" + struct.pack(">I", len(chunks) + 8)
Path(sys.argv[1]).write_bytes(header + chunks)
PYEOF

# 2. Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AIStatusWidget</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.ai-status-widget</string>
    <key>CFBundleName</key>
    <string>AIStatusWidget</string>
    <key>CFBundleDisplayName</key>
    <string>AI 状态小组件</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 3. Bundle collector & setup.html & compile binary
cp "$DIR/collector.py" "$RESOURCES/collector.py"
cp "$DIR/setup.html" "$RESOURCES/setup.html"
chmod +x "$RESOURCES/collector.py"

swiftc -O -module-cache-path /tmp/swift-module-cache -framework Cocoa -framework SwiftUI "$DIR/AIStatusWidget.swift" -o "$MACOS/AIStatusWidget"
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
touch "$APP_DIR"
echo "Built complete Liquid Glass app with AppIcon: $APP_DIR"
