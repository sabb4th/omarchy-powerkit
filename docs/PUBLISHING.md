# Publishing PowerKit

The marketplace's [publishing guide](https://plugins.omarchy.org/publish.html) requires a public repository, a root manifest, README/license, safe installation/removal and a submission issue. Listing approval is performed by its maintainers; it is not a security review.

1. Run `bash check.sh`, `omarchy plugin validate .`, and a Quickshell preview. Check native/source and prebuilt installations plus optional legacy migration in isolated directories. Real hardware writes are tested separately on supported hardware.
2. Keep `Cargo.toml`, `Cargo.lock`, `manifest.json` and the release tag at the same version. The permanent ID is `io.github.sabb4th.powerkit`.
3. Push the reviewed sources and confirm the Check PowerKit workflow passes. Tag `v<VERSION>` and push the tag. The release workflow validates the tag, checks code, builds a release, and publishes the tarball/checksum.
4. Submit an issue to `omacom/omarchy-plugin-marketplace` titled `[Plugin]: PowerKit`, label `submission`, using the body in [marketplace-submission.md](marketplace-submission.md). Category Hardware; tags Bar, Power management, Quickshell.
5. Follow the marketplace's automated validation and maintainer feedback. Do not claim a listing is approved until it appears in the catalogue.

The root `preview.png` is an actual QML capture with simulated data, not a screenshot of private system details. No generated package or build cache is committed. The native installer clones the source launcher; it does not run the optional manual installer. Release tarballs replace the launcher with the compiled binary and include source for review.
