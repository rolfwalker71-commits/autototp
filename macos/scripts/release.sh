#!/bin/zsh
# Baut die App und veröffentlicht sie als GitHub-Release mit ZIP, DMG und icon.png.
#
#   scripts/release.sh                      # Version aus der Info.plist
#   scripts/release.sh 1.2.1                # Version vorher setzen (Build wird hochgezählt)
#   scripts/release.sh 1.2.1 notes.md       # Release-Text aus Datei statt aus dem Editor
#
# Die Assets heissen Autototp-macOS-<version>-arm64.zip, Autototp-macOS-<version>-arm64.dmg
# und icon.png (Letzteres braucht die Landing Page, deshalb exakt dieser Name).
set -euo pipefail
cd "${0:A:h}/.."

plist=Resources/Info.plist
version=${1:-}
notes=${2:-}

if [[ -n $version ]]; then
    build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build + 1))" "$plist"
fi
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
tag=macos-v$version

echo "▸ Tests"
scripts/test.sh >/dev/null

scripts/build-app.sh

app=build/Autototp.app
zip=build/Autototp-macOS-$version-arm64.zip
dmg=build/Autototp-macOS-$version-arm64.dmg
staging=build/dmg

echo "▸ ZIP"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "▸ DMG"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Programme"
hdiutil create -volname "Autototp $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"

# icon.png entsteht bereits in build-app.sh aus AppIcon.icns.
echo "▸ Release $tag"
if [[ -n $notes ]]; then
    gh release create "$tag" "$zip" "$dmg" build/icon.png \
        --target main --latest --title "Autototp für macOS $version" --notes-file "$notes"
else
    gh release create "$tag" "$zip" "$dmg" build/icon.png \
        --target main --latest --title "Autototp für macOS $version" --generate-notes
fi

echo "✔ $tag veröffentlicht"
