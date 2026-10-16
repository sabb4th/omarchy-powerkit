#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cargo test --locked --manifest-path "$root/Cargo.toml"
cargo clippy --locked --manifest-path "$root/Cargo.toml" --all-targets -- -D warnings
cargo fmt --check --manifest-path "$root/Cargo.toml"
bash -n "$root/install.sh" "$root/uninstall.sh" "$root/check.sh"
omarchy-plugin-validate "$root"
if command -v node >/dev/null; then
  node "$root/tests/test_display.cjs"
elif command -v deno >/dev/null; then
  deno run --allow-read --allow-env "$root/tests/test_display.cjs"
else
  echo "Install Node.js or Deno to check bar formatting." >&2
  exit 1
fi
