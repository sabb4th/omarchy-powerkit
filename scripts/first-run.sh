#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-powerkit
mkdir -p -- "$state"
chmod 700 "$state"
# Only one visible prompt, even when several monitors load the widget at once.
exec 9>"$state/setup.lock"
flock 9
bash "$root/scripts/setup.sh" --check && exit 0
if [[ -e $state/setup-deferred ]]; then
  echo 'PowerKit: setup was deferred. Run bash scripts/setup.sh from the plugin directory to retry.' >&2
  exit 1
fi
# The native terminal launcher detaches; wait on a private result file instead.
result=$(mktemp "$state/setup-result.XXXXXX")
rm -- "$result"
trap 'rm -f -- "$result"' EXIT
touch "$state/setup-deferred"
omarchy launch terminal bash -c '
  bash "$1/scripts/setup.sh"
  status=$?
  printf "%s\n" "$status" > "$2"
  if ((status != 0)); then read -r -p "Setup stopped. Press Enter to close."; fi
' powerkit-setup "$root" "$result"
for ((attempt=0; attempt<3600; attempt++)); do
  if [[ -s $result ]]; then
    read -r status < "$result"
    [[ $status == 0 ]] || exit 1
    rm -f -- "$state/setup-deferred"
    exit 0
  fi
  sleep 1
done
echo 'PowerKit: setup window timed out; run scripts/setup.sh to retry.' >&2
exit 1
