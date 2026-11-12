#!/bin/zsh
# Baut PianoFlow.app und installiert sie nach ~/Applications
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/PianoFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PianoFlow "$APP/Contents/MacOS/PianoFlow"
python3 make_demo.py "$APP/Contents/Resources/Fuer Elise (Demo).mid"
[ -f catalog/songs.json ] && cp catalog/songs.json "$APP/Contents/Resources/songs.json"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PianoFlow</string>
  <key>CFBundleDisplayName</key><string>PianoFlow</string>
  <key>CFBundleIdentifier</key><string>de.samuel.pianoflow</string>
  <key>CFBundleExecutable</key><string>PianoFlow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>PianoFlow erkennt über das Mikrofon, welche Töne du auf einem akustischen Klavier spielst.</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>MIDI</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.midi-audio</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/PianoFlow.app
cp -R "$APP" ~/Applications/
echo "Installiert: ~/Applications/PianoFlow.app"
