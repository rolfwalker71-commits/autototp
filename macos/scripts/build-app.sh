#!/bin/zsh
# Builds build/Autototp.app with swiftc directly (works with just the Command Line Tools).
#
#   scripts/build-app.sh             # release build
#   scripts/build-app.sh --install   # also copies the app to /Applications
#
# Signing: uses the first "Apple Development" identity (or AUTOTOTP_SIGN_IDENTITY), so the
# Accessibility permission survives rebuilds; falls back to ad hoc when none exists.
set -euo pipefail
cd "${0:A:h}/.."

app=build/Autototp.app
obj=build/obj
arch=$(uname -m)
target="$arch-apple-macos15.0"

# The macOS 27 SDK needs the SwiftUI macro plugin. Xcode ships it; the Command Line Tools alone
# do not, so then fall back to the newest SDK that works without it.
sdk=${AUTOTOTP_SDK:-$(xcrun --show-sdk-path)}
toolchain=$(dirname "$(dirname "$(xcrun --find swiftc)")")
plugins=( "$toolchain"/lib/swift/host/plugins/*SwiftUIMacros*(N) "${sdk:h:h}"/usr/lib/swift/host/plugins/*SwiftUIMacros*(N) )
if [[ -z "${AUTOTOTP_SDK:-}" && ${#plugins} -eq 0 ]]; then
    fallback=( "${sdk:h}"/MacOSX26*.sdk(N) )
    (( ${#fallback} )) && sdk=${${(On)fallback}[1]}
fi
echo "▸ SDK: ${sdk:t}"

rm -rf "$app" "$obj"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$obj"

echo "▸ Kern kompilieren"
swiftc -O -swift-version 5 -target "$target" -sdk "$sdk" \
    -module-name AutototpCore -parse-as-library -emit-library -static \
    -emit-module -emit-module-path "$obj/AutototpCore.swiftmodule" \
    Sources/AutototpCore/*.swift \
    -o "$obj/libAutototpCore.a"

echo "▸ App kompilieren"
swiftc -O -swift-version 5 -target "$target" -sdk "$sdk" \
    -module-name Autototp \
    -I "$obj" -L "$obj" -lAutototpCore \
    -framework Carbon \
    Sources/Autototp/*.swift Sources/Autototp/Views/*.swift \
    -o "$app/Contents/MacOS/Autototp"

echo "▸ Bundle zusammenstellen"
cp Resources/Info.plist "$app/Contents/Info.plist"

iconset="$obj/AppIcon.iconset"
mkdir -p "$iconset"
# Quick Look renders the SVG (no extra tools needed); sips scales it down.
qlmanage -t -s 1024 -o "$obj" Resources/AppIcon.svg >/dev/null 2>&1
source_icon="$obj/AppIcon.svg.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$source_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$source_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

echo "▸ Signieren"
# A stable identity keeps the Accessibility permission across rebuilds; ad hoc changes it every build.
identity=${AUTOTOTP_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)}
identity=${identity:--}
echo "  Identität: ${identity/#-/ad hoc}"
codesign --force --options runtime --sign "$identity" "$app"

echo "✔ $app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Autototp.app
    cp -R "$app" /Applications/
    echo "✔ /Applications/Autototp.app"
fi
