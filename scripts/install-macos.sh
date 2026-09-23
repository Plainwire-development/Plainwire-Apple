#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo "Plainwire's Mac installer must run on macOS." >&2
  exit 1
fi

repository=Plainwire-development/Plainwire-Apple
archive_name=Plainwire-macOS-universal.zip
destination_dir="$HOME/Applications"
source_app=""
release_tag=latest
mode=auto
launch=true
download_dir=""
stage=""
backup=""
target=""

usage() {
  cat <<'USAGE'
Usage: install-macos.sh [--release TAG | --source | --app PATH] [--destination DIR] [--no-open]

From a checkout, the default is to build with Xcode. When run through curl,
the default is to install the latest GitHub Release. --app installs an existing
Plainwire.app bundle.
USAGE
}

while (($#)); do
  case "$1" in
    --app|--release|--destination)
      if (($# < 2)); then echo "Missing value for $1" >&2; exit 2; fi
      case "$1" in
        --app) source_app=$2; mode=app ;;
        --release) release_tag=$2; mode=release ;;
        --destination) destination_dir=$2 ;;
      esac
      shift 2
      ;;
    --source) mode=source; shift ;;
    --no-open) launch=false; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cleanup() {
  if [[ -n $backup && -d $backup && ! -e $target ]]; then mv "$backup" "$target"; fi
  if [[ -n $stage ]]; then rm -rf "$stage"; fi
  if [[ -n $download_dir ]]; then rm -rf "$download_dir"; fi
}
trap cleanup EXIT

root=""
script_path=${BASH_SOURCE[0]:-}
if [[ -n $script_path && -f $script_path ]]; then
  candidate=$(cd "$(dirname "$script_path")/.." && pwd)
  if [[ -f $candidate/Plainwire.xcodeproj/project.pbxproj ]]; then root=$candidate; fi
fi

if [[ $mode == source || ( $mode == auto && -n $root ) ]]; then
  if [[ -z $root ]]; then echo "--source needs a Plainwire checkout." >&2; exit 1; fi
  developer_dir=${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}
  if [[ -z $developer_dir || $developer_dir == /Library/Developer/CommandLineTools ]]; then
    developer_dir=/Applications/Xcode.app/Contents/Developer
  fi
  if [[ ! -x $developer_dir/usr/bin/xcodebuild ]]; then
    echo "Install Xcode before building Plainwire." >&2
    exit 1
  fi
  export DEVELOPER_DIR=$developer_dir
  if ! xcodebuild -license check >/dev/null 2>&1; then
    echo "Accept the Xcode license in Terminal, then run this script again:" >&2
    echo "  sudo $developer_dir/usr/bin/xcodebuild -license accept" >&2
    exit 1
  fi

  build_dir=${TMPDIR:-/tmp}/plainwire-macos-build
  echo "Building Plainwire…"
  xcodebuild -quiet \
    -project "$root/Plainwire.xcodeproj" -scheme Plainwire \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO build
  source_app=$build_dir/Build/Products/Release/Plainwire.app
elif [[ $mode != app ]]; then
  if [[ $release_tag == latest ]]; then
    release_url=https://github.com/$repository/releases/latest/download
  elif [[ $release_tag =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    release_url=https://github.com/$repository/releases/download/$release_tag
  else
    echo "Release tags must look like 1.2.3 or v1.2.3." >&2
    exit 2
  fi

  download_dir=$(mktemp -d "${TMPDIR:-/tmp}/plainwire-download.XXXXXX")
  echo "Downloading Plainwire…"
  curl -fsSL --retry 3 --connect-timeout 15 \
    -o "$download_dir/$archive_name" "$release_url/$archive_name"
  curl -fsSL --retry 3 --connect-timeout 15 \
    -o "$download_dir/SHA256SUMS.txt" "$release_url/SHA256SUMS.txt"
  (
    cd "$download_dir"
    shasum -a 256 -c SHA256SUMS.txt
  )
  mkdir "$download_dir/unpacked"
  ditto -x -k "$download_dir/$archive_name" "$download_dir/unpacked"
  source_app=$download_dir/unpacked/Plainwire.app
  codesign --verify --strict "$source_app"
fi

if [[ ! -f $source_app/Contents/Info.plist || ! -x $source_app/Contents/MacOS/Plainwire ]]; then
  echo "Plainwire.app is missing or incomplete: $source_app" >&2
  exit 1
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")
if [[ $bundle_id != me.kokonico.plainwire ]]; then
  echo "This is not a Plainwire app: $source_app" >&2
  exit 1
fi

mkdir -p "$destination_dir"
destination_dir=$(cd "$destination_dir" && pwd)
target=$destination_dir/Plainwire.app
stage=$(mktemp -d "$destination_dir/.plainwire-install.XXXXXX")
ditto "$source_app" "$stage/Plainwire.app"
xattr -dr com.apple.quarantine "$stage/Plainwire.app"

if [[ -e $target ]]; then
  backup=$destination_dir/.Plainwire.backup.$$
  mv "$target" "$backup"
fi
mv "$stage/Plainwire.app" "$target"
if [[ -n $backup ]]; then rm -rf "$backup"; backup=""; fi

echo "Installed $target"
if [[ $launch == true ]]; then open "$target"; fi
