---
summary: "RepoPeek release checklist: versioning, Sparkle appcast, signing/notarization, and verification."
read_when:
  - Preparing or validating a RepoPeek release
  - Running package_app/notarize scripts or checking release assets
  - Changing auth storage or keychain entitlements
---

# Release Checklist

## Standard Release Flow

1. Version and changelog
   - Update `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`).
   - Finalize the top section in `CHANGELOG.md`; the header must start with the version.

2. Run validation
   - `pnpm check`
   - `pnpm build`

3. Package and publish
   - `Scripts/release.sh`
   - Builds, signs, notarizes, generates appcast entry plus HTML notes from `CHANGELOG.md`, publishes release assets, and tags/pushes.
   - Requires `REPOPEEK_APP_IDENTITY` or `CODESIGN_IDENTITY`, `APP_STORE_CONNECT_*`, and `SPARKLE_PRIVATE_KEY_FILE`.
   - Set `REPOPEEK_GITHUB_REPOSITORY` if publishing anywhere other than `weirdo-adam/RepoPeek`; make sure `origin` points to the same public repository before running the script.
   - Default Sparkle feed: `https://raw.githubusercontent.com/weirdo-adam/RepoPeek/main/appcast.xml`.
   - Default release downloads: `https://github.com/weirdo-adam/RepoPeek/releases/download/<tag>/`.

4. Sparkle UX verification
   - About -> `Check for Updates...`
   - Menu only shows `Update ready, restart now?` once the update is downloaded.
   - Sparkle dialog shows formatted release notes.
   - Verify the released app does not include `RepoPeekTokenStore=file`.
   - Verify `keychain-access-groups` is present only if the app is signed with a matching provisioning profile. Otherwise leave `REPOPEEK_SKIP_KEYCHAIN_GROUPS` at the release default (`1`) to avoid AMFI launch failures.

## Manual Steps

1. Debug smoke build/tests
   - `Scripts/compile_and_run.sh`
   - Launches the packaged debug bundle from `.build/debug/RepoPeek.app` through LaunchServices.
   - Debug bundles use file-backed auth (`RepoPeekTokenStore=file`) so local launches do not prompt for Keychain access.

2. Local app install
   - `Scripts/install_local_app.sh`
   - Packages a release app for the local architecture, ad-hoc signs it if no local signing identity is configured, installs it to `/Applications/RepoPeek.app`, then launches it through LaunchServices.
   - The script verifies that the installed source bundle does not include `RepoPeekTokenStore=file`.
   - After a successful launch, it removes local packaging artifacts unless `REPOPEEK_KEEP_LOCAL_BUILD_ARTIFACTS=1` is set.

3. Package and notarize
   - `Scripts/package_app.sh [debug|release]`
   - Optional notarization: `NOTARIZE=1 NOTARY_PROFILE="Xcode Notary" Scripts/package_app.sh release`
   - Verify: `spctl --assess --verbose .build/release/RepoPeek.app`
   - Inspect release auth storage: `plutil -p .build/release/RepoPeek.app/Contents/Info.plist | rg RepoPeekTokenStore` should print nothing.

4. Release notes
   - `Scripts/generate-release-notes.sh <version> > RELEASE_NOTES.md`

5. Post-publish asset check
   - `Scripts/check-release-assets.sh <tag>` verifies zip and dSYM assets.
