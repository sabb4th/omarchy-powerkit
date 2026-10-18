# Publishing PowerKit

The marketplace's [publishing guide](https://plugins.omarchy.org/publish.html) requires a public repository, a root manifest, README/license, safe installation/removal and a submission issue. Listing approval is performed by its maintainers; it is not a security review.

1. Run `bash check.sh`, `omarchy plugin validate .`, and a Quickshell preview. Check native/source and prebuilt installations plus optional legacy migration in isolated directories. Real hardware writes are tested separately on supported hardware.
2. Keep `Cargo.toml`, `Cargo.lock`, `manifest.json` and the release tag at the same version. The permanent ID is `io.github.sabb4th.powerkit`.
3. Push the reviewed sources and confirm the Check PowerKit workflow passes. Tag `v<VERSION>` and push the tag. The release workflow validates the tag, checks code, builds a release, and publishes the tarball/checksum.
4. Submit an issue to `omacom/omarchy-plugin-marketplace` titled `[Plugin]: PowerKit`, label `submission`, using the body in [marketplace-submission.md](marketplace-submission.md). Category Hardware; tags Bar, Power management, Quickshell.
5. Follow the marketplace's automated validation and maintainer feedback. Do not claim a listing is approved until it appears in the catalogue.

The root `preview.png` is an actual QML capture with simulated data, not a screenshot of private system details. No generated package or build cache is committed. The native installer clones the source launcher; it does not run the optional manual installer. Release tarballs replace the launcher with the compiled binary and include source for review.

## Updating the existing listing

PowerKit is already listed. Do not submit another new-plugin issue. After the release checks pass, open the marketplace's **Verify or update a listed plugin** form with:

- Verification action: `Verify and publish a newer upstream commit`
- Plugin ID: `io.github.sabb4th.powerkit`
- Repository URL: `https://github.com/sabb4th/omarchy-powerkit`
- Target commit: the full 40-character current upstream HEAD SHA (`git rev-parse HEAD`)
- Verification acknowledgment: checked

Describe the release and its current privileged operations in the notes. An update must be validated and accepted for that exact commit before the marketplace promotes its snapshot. Native first-use dependency preparation must be reviewed before requesting removal of the manual-setup override. Submit the newer commit first, then request standard installation for that exact listed snapshot; only maintainers can approve the installation-label change.
