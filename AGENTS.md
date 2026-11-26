# COLMAP 360 Studio repository instructions

- Greet Dan with “Hello Dan”.
- Use `3GOVideo/colmap-360-studio-community` for Studio pull requests and releases. In this checkout, the remote is named `private`. When Dan requests the 3GOVideo account, verify that account before writing to GitHub.
- Start each upgrade on a new feature or fix branch from the latest `main`. Keep work on that branch and open a pull request into `main`. Squash-merge after review and validation when Dan authorizes the merge.
- Version the native Mac app in `macos-app/Info.plist`. Bump the patch for fixes, the minor version for new features, and the major version for breaking changes. Increment `CFBundleVersion` for each new versioned build. Rebuilding the same version keeps its identifiers. `build_macos_app.sh` reads the version from the plist and uses it in the app filename.
- Before a Mac release, build the app, verify the bundle version and signature, and test the ZIP intended for download. Update the English and Spanish README and release notes. Label the download with its platform and architecture, and identify an ad hoc signed build as such.
- Publish a GitHub release only when Dan asks for it. For future releases, tag the tested, merged commit on `main` and attach the verified archive. Preserve earlier releases, tags, and downloads. Keep the latest Windows Community download visible when publishing a macOS-only update.
