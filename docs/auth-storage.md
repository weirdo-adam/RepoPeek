---
summary: "RepoPeek PAT storage modes: production Keychain and debug file-backed storage."
read_when:
  - Modifying auth/token storage
  - Debugging Keychain prompts during local development
  - Changing package_app.sh, compile_and_run.sh, or debug auth behavior
  - Preparing release signing or entitlement changes
---

# Auth Storage

RepoPeek has two PAT storage modes:

- **Keychain**: production default. The GitLab PAT uses the macOS Keychain.
- **File**: debug/autonomy mode. The PAT is stored as JSON under `~/Library/Application Support/RepoPeek/DebugAuth`.

`TokenStore.shared` chooses the backend in this order:

1. `REPOPEEK_TOKEN_STORE` environment variable.
2. `RepoPeekTokenStore` in the app bundle `Info.plist`.
3. Debug-build file storage fallback.
4. Release-build Keychain fallback.

Accepted file values are `file` and `disk`. Set `REPOPEEK_TOKEN_STORE=keychain` to force Keychain in debug builds.

## Debug App Builds

`Scripts/package_app.sh debug` writes this into the generated app bundle:

```xml
<key>RepoPeekTokenStore</key><string>file</string>
```

That means `pnpm start` and `pnpm restart` launch a file-backed debug bundle from the checkout and must not trigger macOS Keychain prompts during autonomous development. The debug app still signs normally, but it also strips `keychain-access-groups` when no provisioning profile is configured.

SwiftPM test binaries do not have the app bundle `Info.plist`, so debug builds also default to file-backed storage in code. Local `swift test`, `pnpm test`, and the packaged debug app therefore share the same non-Keychain backend unless explicitly overridden.

To force Keychain while debugging:

```sh
REPOPEEK_TOKEN_STORE=keychain pnpm start
```

## Release Builds

Release builds do not write `RepoPeekTokenStore=file`, so they use Keychain by default.

Use `Scripts/install_local_app.sh` when the local `/Applications/RepoPeek.app` needs to be updated from this checkout. That script packages a release app before installing it, uses ad-hoc signing when no local identity is configured, and fails if the bundle contains the debug `RepoPeekTokenStore` flag. After a successful launch it removes local packaging artifacts; set `REPOPEEK_KEEP_LOCAL_BUILD_ARTIFACTS=1` to keep them for debugging.

Developer ID builds currently strip `keychain-access-groups` unless `REPOPEEK_SKIP_KEYCHAIN_GROUPS=0` is set for a properly provisioned build. Without a valid provisioning profile, shipping that entitlement causes AMFI launch failures on newer macOS versions.

## File Backend Notes

The file backend exists for local debug autonomy, not for shipped secrets. It stores the same data shape as Keychain:

- `pat`: GitLab Personal Access Token.

Files are written with `0600` permissions where supported. `TokenStore.clear()` removes the file-backed PAT entry for the configured service.
