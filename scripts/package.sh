#!/usr/bin/env bash
# Package an already-built binary and complete reviewable sources, with checksums.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(jq -r '.version' "$root/manifest.json")
binary=$root/target/release/powerkit
[[ -x $binary ]] || { echo 'Run cargo build --release --locked first.' >&2; exit 1; }
case $(uname -m) in x86_64|aarch64) arch=$(uname -m);; *) echo 'Unsupported release architecture.' >&2; exit 1;; esac
name=powerkit-$version-linux-$arch
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/$name" "$root/dist"
for item in BarWidget.qml BatteryGlyph.qml BatteryModel.qml Dashboard.qml Display.js Panel.qml manifest.json qmldir Cargo.toml Cargo.lock LICENSE README.md README.pt-BR.md CHANGELOG.md SECURITY.md install.sh uninstall.sh check.sh preview.png bin src scripts tests docs; do
  cp -R -- "$root/$item" "$stage/$name/"
done
install -m 0755 "$root/bin/powerkit" "$stage/$name/bin/powerkit-source"
install -m 0755 "$binary" "$stage/$name/bin/powerkit"
archive=$root/dist/$name.tar.gz
tar --exclude=__pycache__ --exclude='*.pyc' -czf "$archive" -C "$stage" "$name"
(cd "$root/dist" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
printf '%s\n' "$archive"
