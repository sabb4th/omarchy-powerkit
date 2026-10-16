### Repository URL

https://github.com/sabb4th/omarchy-powerkit

### Category

Hardware

### Tags

Bar, Power management, Quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

PowerKit is an English-language battery and power-profile bar widget for Omarchy Quattro. It has a native themed panel, seven bar display formats, batctl presets/custom thresholds/persistence, power-profiles-daemon profiles, and hardware-advertised Auto / Inhibit charge / Force discharge controls. Plugin ID: `io.github.sabb4th.powerkit`. MIT licensed; root `preview.png` was captured from our own QML preview using simulated readings.

Native `omarchy plugin add` is supported: the tracked `bin/powerkit` launcher compiles the Rust backend once into the user's XDG cache with locked Cargo dependencies, and rebuilds after source changes. This requires Cargo and registry access for an uncached build. Release archives also contain a prebuilt backend and checksums. No packages or services are installed automatically.

Runtime dependencies: Omarchy Quattro/Quickshell, Ooooze's `batctl-tui` (`/usr/bin/batctl`, not the mesh-networking utility), configured power-profiles-daemon and Omarchy's standard profile bridge, jq/coreutils, and polkit with a graphical authentication agent.

Monitoring is unprivileged and has no network/telemetry. Charge changes explicitly request system authentication: fixed pkexec/batctl for thresholds/persistence, or fixed pkexec/tee with a validated sysfs path and allowlisted supported mode for charge behaviour (the current batctl CLI has no setter). No custom root helper or polkit rule is installed. Charge behaviour is not persisted; threshold persistence is explicitly optional. SECURITY.md documents the boundaries.

Native install/remove does not rewrite unrelated user configuration or reset power settings. The optional manual `install.sh --migrate` is an explicitly requested migration from our previous Battery Studio ID, with configuration/plugin backups. State/cache directories and removal instructions are documented.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
