#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
flags=(--disable-sandbox --cache-path .build/package-cache --config-path .build/package-config --security-path .build/package-security -c release --triple arm64-apple-macosx14.0 -Xswiftc -file-prefix-map -Xswiftc "$PWD=." -Xswiftc -gnone)
swift build "${flags[@]}"
bin_dir="$(swift build "${flags[@]}" --show-bin-path)"
# Assemble a fresh bundle so local files and obsolete resources cannot carry over.
mkdir -p "$PWD/dist"
staging="$(mktemp -d "$PWD/dist/.pauseguard-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/PauseGuard.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/PauseGuard" "$app/Contents/MacOS/PauseGuard"
cp "$bin_dir/PauseGuardAgent" "$app/Contents/MacOS/PauseGuardAgent"
cp Resources/PauseGuard.icns "$app/Contents/Resources/PauseGuard.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
chmod 755 "$app/Contents/MacOS/PauseGuard" "$app/Contents/MacOS/PauseGuardAgent"
# LoginItemManager writes login jobs using Bundle.main.bundleURL only after consent.
/usr/bin/plutil -lint "$app/Contents/Info.plist"
# Release binaries still contain DWARF by default; remove build paths before signing.
xcrun strip -S "$app/Contents/MacOS/PauseGuard" "$app/Contents/MacOS/PauseGuardAgent"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$app/Contents/MacOS/PauseGuardAgent"
  codesign --force --sign - "$app"
  codesign --verify --deep --strict "$app"
fi
bash Scripts/check-app.sh "$app"
if [[ -e "$PWD/dist/PauseGuard.app" ]]; then
  mkdir -p "$PWD/.build/release-backups"
  backup="$(mktemp -d "$PWD/.build/release-backups/previous.XXXXXX")"
  mv "$PWD/dist/PauseGuard.app" "$backup/"
fi
mv "$app" "$PWD/dist/PauseGuard.app"
printf 'Built %s\n' "$PWD/dist/PauseGuard.app"
