#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Testing PlainwireCore…"
swift test --scratch-path "${TMPDIR:-/tmp}/plainwire-verify-build" -Xswiftc -warnings-as-errors

echo "Checking Swift syntax…"
swift_sources=()
while IFS= read -r source; do swift_sources+=("$source"); done < <(
  find App Sources Tests -type f -name '*.swift' | sort
)
swiftc -frontend -parse "${swift_sources[@]}"

echo "Checking project files…"
python3 - <<'PY'
import json
import plistlib
from pathlib import Path

for name in ("Info.plist", "Plainwire-macOS.entitlements", "PrivacyInfo.xcprivacy"):
    with (Path("Resources") / name).open("rb") as file:
        plistlib.load(file)

for path in Path("Resources/Assets.xcassets").rglob("Contents.json"):
    json.loads(path.read_text())

project = Path("Plainwire.xcodeproj/project.pbxproj").read_text()
for directory in (Path("App"), Path("Sources/PlainwireCore")):
    for path in directory.rglob("*.swift"):
        reference = f'path = "{path}";'
        if project.count(reference) != 1:
            raise SystemExit(f"Expected one Xcode reference for {path}")
PY

if command -v plutil >/dev/null 2>&1; then
  plutil -lint Plainwire.xcodeproj/project.pbxproj >/dev/null
fi

echo "Checks passed."
