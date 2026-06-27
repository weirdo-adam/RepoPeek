#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_NAME="${REPOPEEK_APP_NAME:-RepoPeek}"
ARTIFACT_NAME="${REPOPEEK_ARTIFACT_NAME:-RepoPeek}"
APP_EXECUTABLE_NAME="${REPOPEEK_EXECUTABLE_NAME:-RepoPeek}"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_EXECUTABLE_NAME}"
INSTALL_DIR="${REPOPEEK_INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Load signing defaults from Config/Local.xcconfig if present.
if [ -f "${ROOT_DIR}/Config/Local.xcconfig" ]; then
  while IFS='=' read -r rawKey rawValue; do
    key="$(printf '%s' "$rawKey" | sed 's,//.*$,,' | xargs)"
    value="$(printf '%s' "$rawValue" | sed 's,//.*$,,' | xargs)"
    case "$key" in
      CODE_SIGN_IDENTITY|CODESIGN_IDENTITY) CODE_SIGN_IDENTITY="${value}" ;;
      DEVELOPMENT_TEAM) DEVELOPMENT_TEAM="${value}" ;;
      PROVISIONING_PROFILE_SPECIFIER) PROVISIONING_PROFILE_SPECIFIER="${value}" ;;
    esac
  done < <(grep -v '^[[:space:]]*//' "${ROOT_DIR}/Config/Local.xcconfig")
fi

kill_existing() {
  for _ in {1..10}; do
    pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -x "${APP_EXECUTABLE_NAME}" 2>/dev/null || true
    pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null || pgrep -x "${APP_EXECUTABLE_NAME}" >/dev/null || return 0
    sleep 0.2
  done

  log "==> Force killing unresponsive ${APP_NAME} instances"
  for _ in {1..10}; do
    pkill -KILL -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -KILL -x "${APP_EXECUTABLE_NAME}" 2>/dev/null || true
    pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null || pgrep -x "${APP_EXECUTABLE_NAME}" >/dev/null || return 0
    sleep 0.2
  done

  return 1
}

resolve_release_app_bundle() {
  for candidate in \
    "${ROOT_DIR}/.build/apple/Products/Release/${APP_NAME}.app" \
    "${ROOT_DIR}/.build/release/${APP_NAME}.app" \
    "${ROOT_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}.app" \
    "${ROOT_DIR}/.build/x86_64-apple-macosx/release/${APP_NAME}.app"; do
    if [ -d "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

proc_pidpath() {
  python3 - "$1" <<'PY'
import ctypes
import sys

pid = int(sys.argv[1])
buf = ctypes.create_string_buffer(4096)
lib = ctypes.CDLL("/usr/lib/libproc.dylib")
ret = lib.proc_pidpath(pid, buf, ctypes.sizeof(buf))
if ret <= 0:
    raise SystemExit(1)
print(buf.value.decode("utf-8", errors="replace"))
PY
}

ensure_launch_path() {
  local expected_process_resolved expected_process_compare path path_compare
  expected_process_resolved="$1"
  expected_process_compare="$(printf '%s' "${expected_process_resolved}" | tr '[:upper:]' '[:lower:]')"

  for _ in {1..50}; do
    while read -r pid; do
      path="$(proc_pidpath "${pid}" 2>/dev/null || true)"
      path_compare="$(printf '%s' "${path}" | tr '[:upper:]' '[:lower:]')"
      if [ -n "${path}" ] && [ "${path_compare}" = "${expected_process_compare}" ]; then
        return 0
      fi
    done < <(pgrep -x "${APP_EXECUTABLE_NAME}" || true)
    sleep 0.2
  done

  log "ERROR: ${APP_NAME} did not launch from the installed app bundle."
  log "Expected: ${expected_process_resolved}"
  while read -r pid; do
    path="$(proc_pidpath "${pid}" 2>/dev/null || true)"
    if [ -n "${path}" ]; then
      log "Running: ${path}"
    fi
  done < <(pgrep -x "${APP_EXECUTABLE_NAME}" || true)
  return 1
}

cleanup_packaging_outputs() {
  if [ "${REPOPEEK_KEEP_LOCAL_BUILD_ARTIFACTS:-0}" -eq 1 ]; then
    log "==> Keeping local build artifacts"
    return 0
  fi

  log "==> Cleaning local packaging artifacts"
  rm -rf \
    "${ROOT_DIR}/.build/apple/Products/Release" \
    "${ROOT_DIR}/.build/release" \
    "${ROOT_DIR}/.build/release.yaml" \
    "${ROOT_DIR}/.build/arm64-apple-macosx/release" \
    "${ROOT_DIR}/.build/arm64-apple-macosx/release.yaml" \
    "${ROOT_DIR}/.build/x86_64-apple-macosx/release" \
    "${ROOT_DIR}/.build/x86_64-apple-macosx/release.yaml" \
    "${ROOT_DIR}/.build/swiftpm-cache" \
    "${ROOT_DIR}/.build/clang-module-cache"
  rm -f \
    "${ROOT_DIR}/${ARTIFACT_NAME}-"*.zip \
    "${ROOT_DIR}/${ARTIFACT_NAME}-"*.dSYM.zip
}

DEFAULT_IDENTITY="${REPOPEEK_APP_IDENTITY:-${CODE_SIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}}"
IDENTITY="${REPOPEEK_APP_IDENTITY:-${CODESIGN_IDENTITY:-$DEFAULT_IDENTITY}}"
AD_HOC_SIGNING=0
if [ -z "${IDENTITY}" ]; then
  IDENTITY="-"
fi
if [ "${IDENTITY}" = "-" ]; then
  AD_HOC_SIGNING=1
fi

SKIP_KEYCHAIN_GROUPS="${REPOPEEK_SKIP_KEYCHAIN_GROUPS:-0}"
if [ -z "${PROVISIONING_PROFILE_SPECIFIER:-}" ]; then
  SKIP_KEYCHAIN_GROUPS="${REPOPEEK_SKIP_KEYCHAIN_GROUPS:-1}"
fi

log "==> Packaging release app bundle"
if [ "${AD_HOC_SIGNING}" -eq 1 ]; then
  log "==> Using ad-hoc codesigning for local install"
  REPOPEEK_SKIP_KEYCHAIN_GROUPS="${SKIP_KEYCHAIN_GROUPS}" \
    REPOPEEK_UNIVERSAL_RELEASE=0 REPOPEEK_PACKAGE_DSYM=0 \
    bash "${ROOT_DIR}/Scripts/package_app.sh" release
else
  CODESIGN_IDENTITY="${IDENTITY}" REPOPEEK_SKIP_KEYCHAIN_GROUPS="${SKIP_KEYCHAIN_GROUPS}" \
    REPOPEEK_UNIVERSAL_RELEASE=0 REPOPEEK_PACKAGE_DSYM=0 \
    bash "${ROOT_DIR}/Scripts/package_app.sh" release
fi

APP_BUNDLE="$(resolve_release_app_bundle)" || fail "Release app bundle not found."
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
if /usr/libexec/PlistBuddy -c 'Print :RepoPeekTokenStore' "${INFO_PLIST}" >/dev/null 2>&1; then
  fail "Release app bundle unexpectedly contains RepoPeekTokenStore."
fi
if [ "${AD_HOC_SIGNING}" -eq 1 ]; then
  log "==> Ad-hoc codesigning local release app"
  codesign --force --deep --sign - "${APP_BUNDLE}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"

log "==> Killing existing ${APP_NAME} instances"
kill_existing || fail "Existing ${APP_NAME} instance did not stop."

log "==> Installing packaged release app to ${INSTALLED_APP_BUNDLE}"
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALLED_APP_BUNDLE}"
if command -v ditto >/dev/null 2>&1; then
  ditto --noextattr --noqtn "${APP_BUNDLE}" "${INSTALLED_APP_BUNDLE}"
else
  cp -R "${APP_BUNDLE}" "${INSTALLED_APP_BUNDLE}"
fi
xattr -cr "${INSTALLED_APP_BUNDLE}" 2>/dev/null || true

log "==> Launching installed release build"
EXPECTED_PROCESS_RESOLVED="$(cd "${INSTALLED_APP_BUNDLE}" && pwd -P)/Contents/MacOS/${APP_EXECUTABLE_NAME}"
open -n "${INSTALLED_APP_BUNDLE}"
ensure_launch_path "${EXPECTED_PROCESS_RESOLVED}" || exit 1
cleanup_packaging_outputs

log "OK: ${APP_NAME} ${MARKETING_VERSION} (${BUILD_NUMBER}) is installed and running from ${EXPECTED_PROCESS_RESOLVED}."
