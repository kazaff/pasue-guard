#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-$PWD/dist/PauseGuard.app}"
[[ -d "$app/Contents/Resources" ]]
[[ -r "$app/Contents/Resources/LICENSE.txt" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist")" == PauseGuard.icns ]]
sips -g pixelWidth -g pixelHeight "$app/Contents/Resources/PauseGuard.icns"
[[ -x "$app/Contents/MacOS/PauseGuard" ]]
[[ -x "$app/Contents/MacOS/PauseGuardAgent" ]]
/usr/bin/plutil -lint "$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.pauseguard.app ]]
# Login jobs must be generated on the recipient's Mac, using its installed app path.
if [[ -e "$app/Contents/Resources/com.pauseguard.agent.plist" || -e "$app/Contents/Resources/com.pauseguard.login.plist" ]]; then
  echo 'Bundle contains machine-specific login jobs.' >&2; exit 1
fi
for executable in "$app/Contents/MacOS/PauseGuard" "$app/Contents/MacOS/PauseGuardAgent"; do
  [[ "$(lipo -archs "$executable")" == arm64 ]]
done
# Scan binaries too: release debug information can disclose the build machine's home.
while IFS= read -r -d '' bundle_file; do
  if LC_ALL=C grep -aEq '/Users/|/home/|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' "$bundle_file"; then
    echo "Personal path or email found in bundle file: ${bundle_file#"$app"/}" >&2
    exit 1
  fi
done < <(find "$app" -type f -print0)
"$app/Contents/MacOS/PauseGuardAgent" --help
if "$app/Contents/MacOS/PauseGuardAgent" --demo --install --app "$app"; then
  echo 'Agent incorrectly accepted demo install.' >&2; exit 1
fi
if bash Scripts/install-agent.sh --demo; then
  echo 'Install script incorrectly accepted demo option.' >&2; exit 1
fi
if bash Scripts/uninstall-agent.sh --demo; then
  echo 'Uninstall script incorrectly accepted demo option.' >&2; exit 1
fi
if command -v codesign >/dev/null 2>&1; then codesign --verify --deep --strict "$app"; fi
printf 'Bundle smoke checks passed: %s\n' "$app"
