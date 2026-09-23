#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo "Mac releases must be built on macOS." >&2
  exit 1
fi
if (($# != 2)); then
  echo "Usage: ./scripts/package-macos.sh TAG OUTPUT_DIR" >&2
  exit 2
fi

tag=$1
output_dir=$2
root=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${TMPDIR:-/tmp}/plainwire-release-build
archive_name=Plainwire-macOS-universal.zip

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

xcodebuild -quiet \
  -project "$root/Plainwire.xcodeproj" -scheme Plainwire \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" 'ARCHS=arm64 x86_64' \
  CODE_SIGNING_ALLOWED=NO build

app=$build_dir/Build/Products/Release/Plainwire.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ $tag != "v$version" ]]; then
  echo "Tag $tag does not match app version $version." >&2
  exit 1
fi

binary=$app/Contents/MacOS/Plainwire
for arch in arm64 x86_64; do
  if ! lipo -archs "$binary" | tr ' ' '\n' | grep -Fxq "$arch"; then
    echo "The Mac build is missing $arch." >&2
    exit 1
  fi
done

stage=$(mktemp -d "${TMPDIR:-/tmp}/plainwire-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Plainwire.app"
codesign --force --sign - \
  --entitlements "$root/Resources/Plainwire-macOS.entitlements" \
  "$stage/Plainwire.app"
codesign --verify --strict "$stage/Plainwire.app"

ditto -c -k --norsrc --keepParent "$stage/Plainwire.app" "$output_dir/$archive_name"
cp "$root/scripts/install-macos.sh" "$output_dir/install-macos.sh"
(
  cd "$output_dir"
  shasum -a 256 "$archive_name" > SHA256SUMS.txt
)

echo "Created $output_dir/$archive_name"
