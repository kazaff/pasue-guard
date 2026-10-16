#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
developer_dir="$(xcode-select -p)"
flags=(--disable-sandbox --cache-path .build/package-cache --config-path .build/package-config --security-path .build/package-security)
if [[ "$developer_dir" == */CommandLineTools ]]; then
  flags+=(-Xswiftc -F -Xswiftc "$developer_dir/Library/Developer/Frameworks" -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/Frameworks" -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib")
fi
exec swift test "${flags[@]}" "$@"
