#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/PauseGuard.app"
[[ -d "$app/Contents/Resources" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist")" == PauseGuard.icns ]]
sips -g pixelWidth -g pixelHeight "$app/Contents/Resources/PauseGuard.icns"
[[ -x "$app/Contents/MacOS/PauseGuard" ]]
[[ -x "$app/Contents/MacOS/PauseGuardAgent" ]]
/usr/bin/plutil -lint "$app/Contents/Info.plist" "$app/Contents/Resources/com.pauseguard.agent.plist" "$app/Contents/Resources/com.pauseguard.login.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.pauseguard.app ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$app/Contents/Resources/com.pauseguard.agent.plist")" == "$app/Contents/MacOS/PauseGuardAgent" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$app/Contents/Resources/com.pauseguard.agent.plist")" == "$app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$app/Contents/Resources/com.pauseguard.login.plist")" == /usr/bin/open ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$app/Contents/Resources/com.pauseguard.login.plist")" == "$app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$app/Contents/Resources/com.pauseguard.login.plist")" == false ]]
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
