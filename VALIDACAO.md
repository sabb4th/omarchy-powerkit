# Validation · Battery Studio 2.1

Validated on 2026-10-15 on a ThinkPad running Omarchy, batctl and power-profiles-daemon.

- `cargo test --locked`: eight tests passed. Covers threshold capabilities, discrete values, rejected arguments, missing thresholds, weighted multi-battery aggregation, sysfs unit conversion, display preferences, charge-behaviour parsing and battery/mode validation before privileged writes.
- Behaviour validation tests cover all three advertised modes, unsupported modes, malformed input, path traversal, absent batteries and non-battery power supplies. These tests use temporary fixtures and never invoke pkexec.
- `cargo clippy --locked --all-targets -- -D warnings`, `cargo fmt --check`, script syntax and `omarchy-plugin-validate`: passed.
- JavaScript presentation tests using Deno: seven bar formats, eleven battery levels, power and runtime formatting passed.
- `cargo build --release --locked`: optimized binary built successfully.
- Real `battery-studio sample`: detected ThinkPad BAT0, 20–80% thresholds, boot/resume persistence, the current daemon profile, three available profiles and kernel-advertised `auto`, `inhibit-charge`, `force-discharge` with `auto` active. Voltage was read; missing temperature remained null.
- Isolated Quickshell preview with simulated data: compact and expanded layouts loaded without QML errors. The default panel and expanded limit controls were visually inspected. `previews/power-panel-v2.png` is a capture of the current panel using simulated readings.
- Monitor protocol using a temporary XDG state directory: JSON lines, stdin EOF termination, display-format persistence, ignored legacy language changes and 0600 preference-file permissions passed.

The bar battery artwork is unchanged. Display formatting is English-only, and the bar keeps its seven display modes and mouse shortcuts. Settings and the language selector have been removed.

## Scope and limitations

No real battery mode, charge threshold, daemon profile or persistence service was changed for testing. Authenticated writes, boot/resume behaviour and other manufacturers still need validation on the corresponding hardware. The updated installer is tested in a temporary configuration with shell commands mocked; it has not been applied to the actual desktop during development.

The current batctl CLI has no charge-behaviour setter. The plugin uses the same standard kernel attribute as batctl's ThinkPad backend, through fixed `/usr/bin/pkexec` and `/usr/bin/tee` executables, with a power-supply entry checked against the actual sysfs directory and an allowlisted advertised mode passed on stdin. The kernel readback is verified after the write. Mode changes are not persisted by the plugin.

batctl still owns threshold validation, vendor adaptation and threshold persistence. Its `detect` and `status` text formats are parsed because the CLI has no JSON output. Unknown capabilities disable the corresponding controls.

Standalone `qmllint` does not automatically resolve Quickshell's virtual `qs.*` imports; the real Quickshell runtime with installed Omarchy components was used for interface validation. Offscreen runtime notices about Wayland and window masks are platform limitations of the preview.

## Repeat

```bash
bash check.sh
cargo build --release --locked
./target/release/battery-studio sample
```

The compiler used for this session lives under `/tmp`; no permanent system Rust installation was made. Development checks accept Node.js or Deno.
