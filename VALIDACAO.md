# Validation · PowerKit 3.1.0

Validated on 2026-10-15 with Omarchy Quattro and a ThinkPad battery backend.

## 3.1.0 CPU controls and visual refinement

- Ten Rust tests plus two isolated distribution tests pass, along with Clippy, rustfmt, JavaScript presentation checks and Omarchy manifest validation.
- CPU fixtures cover mixed policies, intersection of advertised options, malformed values and policy arguments, Intel Performance/EPP constraints, missing attributes and absent CPU drivers. No authentication or hardware write is performed by these tests.
- Read-only verification of the real notebook reports eight intel_pstate policies, governor powersave and preference balance_power. The available governors and all five advertised preference names are surfaced correctly.
- The real Quickshell runtime loaded simulated Powersave, Intel Performance/EPP-locked and unsupported CPU states without QML errors. Full-width labels, dropdowns, disabled-state readability and compact help were visually inspected.
- An isolated instance of the actual BarWidget (with mock host/model/panel) verified compact, animated width expansion only while charging and completed display-mode transitions. The native bar's tooltip handler ignores the empty tooltip string. No tooltip is configured on the plugin's other buttons either.
- The final preview is saved as preview.png. Charging and active-state bar captures are in previews/bar-charging-v3.1.png and previews/bar-active-v3.1.png. All preview values are simulated.
- Release 3.1.0 compiles locally. CPU writes are live overrides, checked against every active policy and verified after applying; failures can be partial and are reported. No real CPU/battery settings or power profile were changed during validation.

## Previous release validation

## Completed checks

- Eight Rust tests: threshold capabilities/discrete values, malformed actions, missing thresholds, weighted multi-battery aggregation, sysfs unit conversion, display preferences, advertised charge behaviours, and battery/mode/path validation before privileged writes.
- `cargo clippy --locked --all-targets -- -D warnings`, `cargo fmt --check`, shell syntax and JavaScript presentation tests for seven display modes and eleven battery levels passed.
- Both the installed Omarchy validator and the official validator at revision `246f33a2fef66411c990860d88e0823ae83987fc` accepted the root manifest/layout.
- Two isolated distribution tests passed: native source-launcher caching/source-change rebuild and explicitly requested migration preserving bar position/custom settings, with configuration/plugin backups and archive-based removal. Migration integration requires `/usr/bin/batctl` and is skipped on CI hosts without that documented runtime dependency.
- The real source launcher compiled locked Rust dependencies in a temporary XDG cache, forwarded a request to the Rust binary, then reused the binary on a second invocation. No privileged operation was performed.
- A temporary legacy state directory was read successfully; subsequent preference writes used the new PowerKit directory and left legacy preferences untouched.
- Optimized release compilation and checksummed packaging passed. The archive includes the executable, sources, original source launcher, manifest, UI, documentation and license; build caches and Python bytecode are excluded.
- Quickshell's real offscreen runtime loaded the compact/expanded panel without QML errors. The final solid charging bolt sits to the left of the battery. The root `preview.png` is a capture with simulated readings, not private system data.
- Prior read-only hardware verification detected ThinkPad BAT0, 20–80% thresholds, boot/resume persistence, the current daemon profile, three profiles and all three charge behaviours. No real battery settings were changed for testing.

## Limits

Authenticated writes and boot/resume behaviour still require hardware testing. The plugin delegates threshold/vendor handling to batctl and rejects unsupported behaviour modes before asking for authentication. Other laptop models are not claimed to have been tested.

The current batctl CLI has no charge-behaviour setter. PowerKit uses batctl's standard kernel attribute through fixed pkexec/tee executables, a validated real power-supply entry and an allowlisted advertised mode passed over stdin. Kernel readback is checked after writing. Behaviour is not persisted by PowerKit; threshold persistence is opt-in.

Monitoring has no network/telemetry. A first source build can download locked dependencies from the user's configured Cargo registry. The runtime thereafter uses local files/tools only. `SECURITY.md` documents privilege boundaries and persistent files.

The native installer clones source without running `install.sh`; the tracked source launcher makes that flow work. The optional `--migrate` installer is the only path that rewrites the old widget ID in backed-up shell configuration. The actual desktop installation was not modified by the distribution tests.

Standalone `qmllint` cannot automatically resolve Quickshell's virtual `qs.*` imports; UI verification used the real Quickshell runtime. Offscreen notices about Wayland and window masks come from the preview platform.

## Reproduce

```bash
bash check.sh
omarchy plugin validate .
cargo build --release --locked
bash scripts/package.sh
./target/release/powerkit sample
```

Local compilation used a temporary Rust toolchain under `/tmp`; no permanent system compiler installation was made. Marketplace approval is a separate maintainer decision after automated submission checks.
