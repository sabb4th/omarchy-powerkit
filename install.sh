#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_id=io.github.sabb4th.powerkit
config_base=${XDG_CONFIG_HOME:-$HOME/.config}
state_base=${XDG_STATE_HOME:-$HOME/.local/state}
target=$config_base/omarchy/plugins/$plugin_id
state=$state_base/omarchy-powerkit
[[ $EUID != 0 ]] || { echo 'Run as your normal user.' >&2; exit 1; }
prebuilt=
migrate=false
while (( $# )); do
  case "$1" in
    --with-controls|--monitor-only) shift ;;
    --migrate) migrate=true; shift ;;
    --prebuilt)
      [[ $# -ge 2 ]] || { echo '--prebuilt requires a binary path' >&2; exit 2; }
      prebuilt=$(realpath -- "$2")
      shift 2 ;;
    *) echo 'Usage: bash install.sh [--prebuilt BINARY] [--migrate]' >&2; exit 2 ;;
  esac
done
for tool in omarchy omarchy-shell omarchy-plugin-validate omarchy-powerprofiles-set; do
  command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; exit 1; }
done
[[ ! -L $target ]] || { echo "Symlink destination: $target" >&2; exit 1; }
legacy=$config_base/omarchy/plugins/local.battery-studio
shell_config=$config_base/omarchy/shell.json
if [[ -e $legacy || -L $legacy ]]; then
  [[ ! -L $legacy ]] || { echo "Refusing legacy symlink: $legacy" >&2; exit 1; }
  [[ $migrate == true ]] || { echo 'Legacy Battery Studio detected. Use --migrate to back up and replace its widget in place.' >&2; exit 2; }
fi
# Prepare dependencies before building; prebuilt installs do not need a compiler.
if [[ -n $prebuilt ]]; then
  bash "$root/scripts/setup.sh" --runtime
else
  bash "$root/scripts/setup.sh"
fi
for tool in powerprofilesctl pkexec jq; do
  command -v "$tool" >/dev/null || { echo "Missing dependency after setup: $tool" >&2; exit 1; }
done
[[ -x /usr/bin/tee ]] || { echo "Missing dependency: /usr/bin/tee" >&2; exit 1; }
[[ -x /usr/bin/batctl ]] || { echo 'Install batctl-tui (Ooooze/batctl), which provides /usr/bin/batctl.' >&2; exit 1; }
if [[ $migrate == true && -f $shell_config ]]; then
  jq -e 'type == "object"' "$shell_config" >/dev/null
fi
# Build and validate before replacing the installed plugin.
if [[ -z $prebuilt ]]; then
  command -v cargo >/dev/null || { echo 'Install Rust/Cargo, or use --prebuilt target/release/powerkit after a build.' >&2; exit 1; }
  cargo build --release --locked --manifest-path "$root/Cargo.toml" --target-dir "$root/target"
  prebuilt=$root/target/release/powerkit
fi
[[ -f $prebuilt && -x $prebuilt ]] || { echo "Invalid executable: $prebuilt" >&2; exit 1; }
omarchy-plugin-validate "$root"
mkdir -p -- "$(dirname -- "$target")" "$state/backups"
stage=$(mktemp -d "$(dirname -- "$target")/.powerkit.XXXXXX")
backup=
committed=false
cleanup() {
  if [[ $committed != true && -n $backup && ! -e $target ]]; then mv -- "$backup" "$target"; fi
  if [[ -d $stage ]]; then rm -rf -- "$stage"; fi
}
trap cleanup EXIT
install -d "$stage/bin"
install -m 0755 "$prebuilt" "$stage/bin/powerkit"
for file in BarWidget.qml BatteryGlyph.qml BatteryModel.qml Dashboard.qml Panel.qml Display.js manifest.json qmldir LICENSE; do
  install -m 0644 "$root/$file" "$stage/$file"
done
if [[ -e $target ]]; then
  backup=$state/backups/$plugin_id-$(date +%Y%m%d-%H%M%S)-$$
  mv -- "$target" "$backup"
fi
mv -- "$stage" "$target"
committed=true
migrated=false
if [[ $migrate == true ]]; then
  stamp=$(date +%Y%m%d-%H%M%S)-$$
  if [[ -f $shell_config ]] && jq -e '.. | strings | select(. == "local.battery-studio")' "$shell_config" >/dev/null; then
    cp -p -- "$shell_config" "$state/backups/shell.json-$stamp"
    config_stage=$(mktemp "$config_base/omarchy/.powerkit-config.XXXXXX")
    if ! jq --arg old 'local.battery-studio' --arg new "$plugin_id" 'walk(if type == "string" and . == $old then $new else . end)' "$shell_config" > "$config_stage"; then
      rm -f -- "$config_stage"
      exit 1
    fi
    chmod --reference="$shell_config" "$config_stage"
    mv -- "$config_stage" "$shell_config"
    migrated=true
  fi
  if [[ -d $legacy ]]; then mv -- "$legacy" "$state/backups/local.battery-studio-$stamp"; fi
fi
omarchy-shell shell rescanPlugins
# Migration preserves the old layout and enabled state; ordinary installs enable once.
if [[ $migrated != true ]] && ! omarchy plugin list --json 2>/dev/null | jq -e --arg id "$plugin_id" '.. | objects | select(.id? == $id and .enabled? == true)' >/dev/null 2>&1; then
  omarchy plugin enable "$plugin_id" --section right
fi
printf 'PowerKit installed: %s\n' "$target"
printf 'Bar icons and display formats are preserved. Charge controls use system authentication.\n'
