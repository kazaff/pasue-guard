#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
flags=(--disable-sandbox --cache-path .build/package-cache --config-path .build/package-config --security-path .build/package-security -c release)
swift build "${flags[@]}"
bin_dir="$(swift build "${flags[@]}" --show-bin-path)"
app="$PWD/dist/PauseGuard.app"
# Only replace our generated bundle, never a caller-provided path.
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/PauseGuard" "$app/Contents/MacOS/PauseGuard"
cp "$bin_dir/PauseGuardAgent" "$app/Contents/MacOS/PauseGuardAgent"
cp Resources/PauseGuard.icns "$app/Contents/Resources/PauseGuard.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
chmod 755 "$app/Contents/MacOS/PauseGuard" "$app/Contents/MacOS/PauseGuardAgent"
"$app/Contents/MacOS/PauseGuardAgent" --print-plist --app "$app" > "$app/Contents/Resources/com.pauseguard.agent.plist"
"$app/Contents/MacOS/PauseGuardAgent" --print-login-plist --app "$app" > "$app/Contents/Resources/com.pauseguard.login.plist"
/usr/bin/plutil -lint "$app/Contents/Info.plist" "$app/Contents/Resources/com.pauseguard.agent.plist" "$app/Contents/Resources/com.pauseguard.login.plist"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$app/Contents/MacOS/PauseGuardAgent"
  codesign --force --sign - "$app"
  codesign --verify --deep --strict "$app"
fi
printf 'Built %s\n' "$app"
