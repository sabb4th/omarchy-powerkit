# PowerKit

Battery care and power profiles for the **Omarchy Quattro** bar. PowerKit combines a Rust backend, a native QML panel, [batctl](https://github.com/Ooooze/batctl) charge limits and power-profiles-daemon profiles.

![PowerKit panel with simulated battery readings](preview.png)

## Install

Requires Omarchy Quattro's Quickshell plugin API, a configured `power-profiles-daemon`, Ooooze's **`batctl-tui`** (`/usr/bin/batctl`), Rust/Cargo for source installations, `jq`, coreutils and a running graphical polkit agent. The unrelated mesh-networking tool also named batctl is not supported. No packages or services are installed or enabled automatically.

```bash
omarchy plugin add https://github.com/sabb4th/omarchy-powerkit.git --enable
```

The marketplace/native installer clones this repository. `bin/powerkit` builds the backend on first use using the locked Cargo dependencies, then runs the cached executable. Compilation may take a little while and needs access to your configured Cargo registry; it never runs as root. Later source changes create a new build cache. There is no background downloader or external binary service.

If Cargo is missing, install Rust using your normal package-management flow (on Omarchy, `omarchy pkg add rust`). For a build-free installation, download the Linux x86_64 archive and matching checksum from [Releases](https://github.com/sabb4th/omarchy-powerkit/releases), verify and unpack them, then run `bash install.sh --prebuilt bin/powerkit` inside the extracted directory. The archive's `bin/powerkit` is the compiled executable, not the source launcher.

## Use

- **Left-click:** open or close the panel. **Escape:** close it.
- **Right-click:** cycle seven bar formats. **Middle-click:** refresh.
- **Profiles:** Saver → Balanced → Performance, limited to profiles actually offered by the daemon. Uses Omarchy's standard source-aware bridge to remember the AC/battery choice.
- **Charge behaviour:** Auto, Inhibit charge and Force discharge, restricted to the selected battery's advertised modes. A short description explains the current mode.
- **Charge limits:** expand for four hardware-adapted batctl presets, custom start/stop limits, boot/resume persistence and saved-limit restoration.

The panel shows health, charge cycles, full/design capacity, power and estimated runtime or time to the charge limit. Temperature and voltage appear when temperature telemetry exists. Missing values display `—`. The interface is English; the appearance follows your Omarchy theme.

**Charge behaviour applies to the selected battery. Thresholds apply to all batteries through batctl.** Auto follows normal charging policy and limits. Inhibit charge pauses charging; power routing depends on hardware. Force discharge uses the battery even on AC power: select Auto to stop it. Behaviour is not saved or replayed by PowerKit. The persistence switch saves **thresholds only**. When persistent thresholds change, PowerKit updates the saved values too; a failed save is reported separately from live application.

The charging indicator is a solid lightning bolt to the **left** of the battery. The battery fill remains solid, without a grey charging overlay.

## Permissions and dependencies

Read-only monitoring requires no authentication. Charge changes request standard system authentication through polkit. Thresholds/persistence use `pkexec /usr/bin/batctl`; behaviour uses the same kernel `charge_behaviour` interface as batctl's backend through a validated `pkexec /usr/bin/tee` operation, because batctl's current CLI has no setter. Profile changes use the daemon's normal permissions. No custom root helper or polkit policy is installed. See [SECURITY.md](SECURITY.md) for exact privilege boundaries.

QML is the shell's frontend format; the backend is Rust. The daemon's own `powerprofilesctl` may internally use Python. Runtime network access and telemetry are not used.

## Update and remove

```bash
omarchy plugin update io.github.sabb4th.powerkit
omarchy plugin remove io.github.sabb4th.powerkit
```

For a manually copied installation, rerun `install.sh` to update and use `bash uninstall.sh` to disable and archive it. Removing PowerKit does not reset thresholds, modes, batctl services or power profiles. Persistent files are intentionally retained:

| Location | Contents |
| --- | --- |
| `$XDG_STATE_HOME/omarchy-powerkit` (default `~/.local/state/omarchy-powerkit`) | Private display preferences and manual-installer backups |
| `$XDG_CACHE_HOME/omarchy-powerkit` (default `~/.cache/omarchy-powerkit`) | Compiled source-launcher cache |
| `/etc/batctl.conf` and batctl's systemd units | Managed by batctl only when persistence is explicitly requested |

## Upgrade from Battery Studio / the old TLP repository

The project was renamed from `tlp-omarchy-plugin`; the new permanent plugin ID is `io.github.sabb4th.powerkit`. From a source checkout:

```bash
bash install.sh --migrate
# Or use an already-built backend:
bash install.sh --migrate --prebuilt target/release/powerkit
```

Only `--migrate` authorizes the installer to back up `shell.json`, replace the exact old `local.battery-studio` ID in place and archive the old plugin directory. It preserves the bar position and other widget settings. Ordinary installation does not rewrite that configuration. Display preferences fall back to the old state directory until first saved under the new name. Old histories, TLP helper files and TLP configuration remain untouched and unused.

## Development

```bash
bash check.sh
cargo build --release --locked
./target/release/powerkit sample
bash scripts/package.sh
```

Checks require Rust `rustfmt`/`clippy`, Python 3 for isolated distribution tests, jq, and Node.js or Deno. The Omarchy validator runs when available locally; CI also runs the official validator pinned to a known Omarchy revision. GitHub Actions tests and packages each push; version tags produce checksummed Linux x86_64 release archives containing the executable and reviewable sources.

The Rust process exchanges JSON lines with QML, polls every 5 seconds while open and 30 seconds otherwise, and exits on stdin EOF. Display preferences are atomically written with mode 0600. The launcher cache key includes the manifest, lockfile and Rust source, so native plugin updates rebuild when needed.

See [validation notes](VALIDACAO.md), [marketplace submission](docs/marketplace-submission.md) and [release checklist](docs/PUBLISHING.md). MIT license; UI structure is inspired by Omarchy's standard power panel. The preview uses simulated readings. Older screenshots under `previews/` document previous versions.
