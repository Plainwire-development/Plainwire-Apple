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
build_dir=${PLAINWIRE_RELEASE_BUILD_DIR:-${TMPDIR:-/tmp}/plainwire-release-build}
packages_dir=${PLAINWIRE_RELEASE_PACKAGES_DIR:-$build_dir/SourcePackages}
archive_name=Plainwire-macOS-universal.zip
swap_name=plainwire-swap

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

xcodebuild -quiet \
  -project "$root/Plainwire.xcodeproj" -scheme Plainwire \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" -clonedSourcePackagesDirPath "$packages_dir" 'ARCHS=arm64 x86_64' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

app=$build_dir/Build/Products/Release/Plainwire.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ ${tag#v} != "$version" ]]; then
  echo "Tag $tag does not match app version $version." >&2
  exit 1
fi

binary=$app/Contents/MacOS/Plainwire
rtc_binary=$app/Contents/Frameworks/WebRTC.framework/WebRTC
for arch in arm64 x86_64; do
  if ! lipo -archs "$binary" | tr ' ' '\n' | grep -Fxq "$arch"; then
    echo "The Mac build is missing $arch." >&2
    exit 1
  fi
  if ! lipo -archs "$rtc_binary" | tr ' ' '\n' | grep -Fxq "$arch"; then
    echo "The native calling framework is missing $arch." >&2
    exit 1
  fi
done
if [[ ! -f $app/Contents/Resources/WebRTC-LICENSE.txt ]]; then
  echo "The native calling license is missing from the app bundle." >&2
  exit 1
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/plainwire-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Plainwire.app"
codesign --force --sign - "$stage/Plainwire.app/Contents/Frameworks/WebRTC.framework"
codesign --force --sign - \
  --entitlements "$root/Resources/Plainwire-macOS.entitlements" \
  "$stage/Plainwire.app"
codesign --verify --deep --strict "$stage/Plainwire.app"

ditto -c -k --norsrc --keepParent "$stage/Plainwire.app" "$output_dir/$archive_name"
cp "$root/scripts/install-macos.sh" "$output_dir/install-macos.sh"
cp "$root/scripts/update-macos.sh" "$output_dir/update-macos.sh"
clang -arch arm64 -arch x86_64 -O2 -Wall -Wextra -Werror \
  "$root/scripts/plainwire-swap.c" -o "$output_dir/$swap_name"
codesign --force --sign - "$output_dir/$swap_name"
codesign --verify --strict "$output_dir/$swap_name"
(
  cd "$output_dir"
  shasum -a 256 "$archive_name" "$swap_name" > SHA256SUMS.txt
)

echo "Created $output_dir/$archive_name"
