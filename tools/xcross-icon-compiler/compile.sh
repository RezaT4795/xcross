#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo 'Usage: compile.sh <Flutter project root> <iOS flavor>' >&2
  exit 2
fi

project_root="$(realpath "$1")"
flavor="$2"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
assets="$project_root/ios/Runner/Assets.xcassets"
icon="AppIcon-$flavor"
output="$project_root/build/xcross-icon-preview/$flavor"

if [[ ! -d "$assets/$icon.appiconset" ]]; then
  printf 'Icon set missing: %s\n' "$assets/$icon.appiconset" >&2
  exit 3
fi

swift run -c release --package-path "$script_dir" xcross-icon "$assets" "$icon" "$output"

python3 - "$output" "$icon" <<'PY'
from pathlib import Path
import plistlib
import sys

root, expected_name = Path(sys.argv[1]), sys.argv[2]
car = root / 'Assets.car'
plist = root / 'IconPlistAdditions.plist'
assert car.is_file() and car.stat().st_size > 0, f'Missing or empty {car}'
with plist.open('rb') as f:
    data = plistlib.load(f)
assert data['CFBundleIconName'] == expected_name, data['CFBundleIconName']
assert data['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == expected_name
assert any(root.glob('*.png')), 'No icon PNG fallbacks emitted'
print('Icon catalog output: PASS')
print('Plist keys:', ', '.join(sorted(data.keys())))
print('PNG fallbacks:', len(list(root.glob('*.png'))))
PY
