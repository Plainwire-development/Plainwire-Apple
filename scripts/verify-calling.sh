#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $(uname -s) != Darwin ]]; then
  echo "Native calling smoke checks require macOS and Xcode." >&2
  exit 1
fi

build_dir=${PLAINWIRE_CALL_BUILD_DIR:-${TMPDIR:-/tmp}/plainwire-call-verify-build}
packages_dir=${PLAINWIRE_CALL_PACKAGES_DIR:-$build_dir/SourcePackages}
mkdir -p "$build_dir"

xcodebuild -quiet -project Plainwire.xcodeproj -scheme Plainwire \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" -clonedSourcePackagesDirPath "$packages_dir" \
  CODE_SIGNING_ALLOWED=NO build

frameworks_dir=$build_dir/Build/Products/Debug
xcrun swiftc -swift-version 6 -warnings-as-errors \
  -F "$frameworks_dir" -framework WebRTC \
  -Xlinker -rpath -Xlinker "$frameworks_dir" \
  Sources/PlainwireCore/*.swift App/Calling/CallController.swift \
  App/Calling/NativeCallPeer.swift Tests/Manual/CallingSmoke.swift \
  -o "$build_dir/plainwire-calling-smoke"
"$build_dir/plainwire-calling-smoke"

app_sources=()
while IFS= read -r source; do app_sources+=("$source"); done < <(
  find App Sources -type f -name '*.swift' ! -name 'PlainwireApp.swift' | sort
)
xcrun swiftc -swift-version 6 -O -warnings-as-errors \
  -F "$frameworks_dir" -framework WebRTC \
  -Xlinker -rpath -Xlinker "$frameworks_dir" \
  "${app_sources[@]}" \
  Tests/Manual/CallPanelSmoke.swift -o "$build_dir/plainwire-call-panel-smoke"
"$build_dir/plainwire-call-panel-smoke"
