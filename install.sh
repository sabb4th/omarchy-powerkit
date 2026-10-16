#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_id=local.battery-studio
config_base=${XDG_CONFIG_HOME:-$HOME/.config}
state_base=${XDG_STATE_HOME:-$HOME/.local/state}
target=$config_base/omarchy/plugins/$plugin_id
state=$state_base/omarchy-battery-studio
[[ $EUID != 0 ]] || { echo 'Run as your normal user.' >&2; exit 1; }
prebuilt=
while (( $# )); do
  case "$1" in
    --with-controls|--monitor-only) shift ;;
    --prebuilt)
      [[ $# -ge 2 ]] || { echo '--prebuilt requires a binary path' >&2; exit 2; }
      prebuilt=$(realpath -- "$2")
      shift 2 ;;
    *) echo 'Usage: bash install.sh [--prebuilt BINARY]' >&2; exit 2 ;;
  esac
done
for tool in omarchy omarchy-shell omarchy-plugin-validate powerprofilesctl omarchy-powerprofiles-set pkexec jq; do
  command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; exit 1; }
done
[[ -x /usr/bin/tee ]] || { echo "Missing dependency: /usr/bin/tee" >&2; exit 1; }
[[ -x /usr/bin/batctl ]] || { echo 'Install batctl-tui (Ooooze/batctl), which provides /usr/bin/batctl.' >&2; exit 1; }
[[ ! -L $target ]] || { echo "Symlink destination: $target" >&2; exit 1; }
# Build and validate before replacing the installed plugin.
if [[ -z $prebuilt ]]; then
  command -v cargo >/dev/null || { echo 'Install Rust/Cargo, or use --prebuilt target/release/battery-studio after a build.' >&2; exit 1; }
  cargo build --release --locked --manifest-path "$root/Cargo.toml" --target-dir "$root/target"
  prebuilt=$root/target/release/battery-studio
fi
[[ -f $prebuilt && -x $prebuilt ]] || { echo "Invalid executable: $prebuilt" >&2; exit 1; }
omarchy-plugin-validate "$root"
mkdir -p -- "$(dirname -- "$target")" "$state/backups"
stage=$(mktemp -d "$(dirname -- "$target")/.battery-studio.XXXXXX")
backup=
committed=false
cleanup() {
  if [[ $committed != true && -n $backup && ! -e $target ]]; then mv -- "$backup" "$target"; fi
  if [[ -d $stage ]]; then rm -rf -- "$stage"; fi
}
trap cleanup EXIT
install -d "$stage/bin"
install -m 0755 "$prebuilt" "$stage/bin/battery-studio"
for file in BarWidget.qml BatteryGlyph.qml BatteryModel.qml Dashboard.qml Panel.qml Display.js manifest.json qmldir LICENSE; do
  install -m 0644 "$root/$file" "$stage/$file"
done
if [[ -e $target ]]; then
  backup=$state/backups/$plugin_id-$(date +%Y%m%d-%H%M%S)-$$
  mv -- "$target" "$backup"
fi
mv -- "$stage" "$target"
committed=true
omarchy-shell shell rescanPlugins
# Existing widget placement and display preferences survive the upgrade.
if ! omarchy plugin list --json 2>/dev/null | jq -e --arg id "$plugin_id" '.. | objects | select(.id? == $id and .enabled? == true)' >/dev/null 2>&1; then
  omarchy plugin enable "$plugin_id" --section right
fi
printf 'Battery Studio installed: %s\n' "$target"
printf 'Bar icons and display formats are preserved. Charge controls use system authentication.\n'
