#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo "Plainwire's updater runs on macOS." >&2
  exit 1
fi

repository=Plainwire-development/Plainwire-Apple
archive_name=Plainwire-macOS-universal.zip
helper_name=plainwire-swap
destination_dir="$HOME/Applications"
release_tag=latest
launch=true
force=false
stage=""

version_at_least() {
  awk -v current="$1" -v release="$2" 'BEGIN {
    split(current, a, "."); split(release, b, ".");
    for (i = 1; i <= 3; i++) {
      if (a[i] + 0 > b[i] + 0) exit 0;
      if (a[i] + 0 < b[i] + 0) exit 1;
    }
    exit 0;
  }'
}

usage() {
  cat <<'USAGE'
Usage: update-macos.sh [--release TAG] [--destination DIR] [--no-open] [--force]

Downloads and verifies a Plainwire release, then atomically swaps the Mac app.
The current app is left intact if verification or the swap fails.
USAGE
}

while (($#)); do
  case "$1" in
    --release|--destination)
      if (($# < 2)); then echo "Missing value for $1" >&2; exit 2; fi
      if [[ $1 == --release ]]; then release_tag=$2; else destination_dir=$2; fi
      shift 2
      ;;
    --no-open) launch=false; shift ;;
    --force) force=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $release_tag == latest ]]; then
  latest_url=$(curl -fsSIL --retry 3 --connect-timeout 15 \
    -o /dev/null -w '%{url_effective}' "https://github.com/$repository/releases/latest")
  case "$latest_url" in
    "https://github.com/$repository/releases/tag/"*) release_tag=${latest_url##*/} ;;
    *) echo "Could not find the latest Plainwire release." >&2; exit 1 ;;
  esac
fi
if [[ ! $release_tag =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tags must look like 1.2.3 or v1.2.3." >&2
  exit 2
fi
release_version=${release_tag#v}
release_url="https://github.com/$repository/releases/download/$release_tag"

mkdir -p "$destination_dir"
destination_dir=$(cd "$destination_dir" && pwd -P)
target="$destination_dir/Plainwire.app"
if [[ -L $target ]]; then
  echo "The installed app is a symbolic link. Install a regular Plainwire.app first." >&2
  exit 1
fi
if [[ -e $target && ! -d $target ]]; then
  echo "The Plainwire destination is not an app directory: $target" >&2
  exit 1
fi

current_version=""
if [[ -d $target ]]; then
  current_plist="$target/Contents/Info.plist"
  if [[ ! -f $current_plist || ! -x $target/Contents/MacOS/Plainwire ]]; then
    echo "The installed Plainwire.app is incomplete. It was not changed." >&2
    exit 1
  fi
  current_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$current_plist")
  if [[ $current_id != me.kokonico.plainwire ]]; then
    echo "The destination contains another app. It was not changed." >&2
    exit 1
  fi
  current_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$current_plist")
  if [[ $force == false && $current_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if version_at_least "$current_version" "$release_version"; then
      echo "Plainwire $current_version is already installed; no update is needed."
      exit 0
    fi
  fi
fi

cleanup() {
  if [[ -n $stage && -d $stage ]]; then rm -rf "$stage"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stage=$(mktemp -d "$destination_dir/.plainwire-update.XXXXXX")
echo "Downloading Plainwire ${release_version}..."
for asset in "$archive_name" "$helper_name" SHA256SUMS.txt; do
  curl -fsSL --retry 3 --connect-timeout 15 \
    -o "$stage/$asset" "$release_url/$asset"
done
(
  cd "$stage"
  for asset in "$archive_name" "$helper_name"; do
    expected=$(awk -v name="$asset" '$2 == name { print $1 }' SHA256SUMS.txt)
    actual=$(shasum -a 256 "$asset" | awk '{ print $1 }')
    if [[ ! $expected =~ ^[0-9a-fA-F]{64}$ || $actual != "$expected" ]]; then
      echo "Plainwire $asset failed its SHA-256 check." >&2
      exit 1
    fi
  done
)

mkdir "$stage/unpacked"
ditto -x -k "$stage/$archive_name" "$stage/unpacked"
staged_app="$stage/Plainwire.app"
ditto "$stage/unpacked/Plainwire.app" "$staged_app"
if [[ ! -f $staged_app/Contents/Info.plist || ! -x $staged_app/Contents/MacOS/Plainwire ]]; then
  echo "The downloaded Plainwire.app is incomplete. The installed app was not changed." >&2
  exit 1
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staged_app/Contents/Info.plist")
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staged_app/Contents/Info.plist")
if [[ $bundle_id != me.kokonico.plainwire || $bundle_version != "$release_version" ]]; then
  echo "The downloaded app identity or version is wrong. The installed app was not changed." >&2
  exit 1
fi
codesign --verify --strict "$staged_app"
chmod 755 "$stage/$helper_name"
codesign --verify --strict "$stage/$helper_name"
xattr -dr com.apple.quarantine "$staged_app"

if pgrep -x Plainwire >/dev/null 2>&1; then
  osascript -e 'tell application id "me.kokonico.plainwire" to quit' >/dev/null 2>&1 || true
  for ((attempt=0; attempt<20; attempt++)); do
    if ! pgrep -x Plainwire >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  if pgrep -x Plainwire >/dev/null 2>&1; then
    echo "Please quit Plainwire, then run the updater again. No files were changed." >&2
    exit 1
  fi
fi

if [[ -d $target ]]; then
  "$stage/$helper_name" "$target" "$staged_app"
else
  mv "$staged_app" "$target"
fi

echo "Updated Plainwire to $release_version at $target"
if [[ $launch == true ]]; then open "$target"; fi
