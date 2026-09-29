#!/usr/bin/env bash
# Dev Container Feature: d2
# Installs the D2 declarative diagramming language CLI and configures
# default TALA diagram layout.
# Runs at image build time as root via the devcontainers CLI.
set -euo pipefail

VERSION="${VERSION:-latest}"
PREFIX="${PREFIX:-/usr/local}"

fail() {
  echo "[d2] ERROR: $*" >&2
  exit 1
}

reject_newlines() {
  case "$1" in
    *$'\n'*|*$'\r'*) fail "'$2' must not contain newlines" ;;
  esac
}

reject_newlines "$VERSION" "version"

case "$VERSION" in
  *[[:space:]\'\"\`\$]*) fail "Invalid characters in version '$VERSION'" ;;
esac

if [ "$VERSION" != "latest" ]; then
  VERSION="v${VERSION#v}"
fi

echo "[d2] Installing D2 (version=${VERSION}, prefix=${PREFIX})..."

# ---------------------------------------------------------------------------
# Base image & runtime compatibility check (glibc required; Alpine/musl unsupported)
# ---------------------------------------------------------------------------
if [ -f /etc/alpine-release ] || (command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi 'musl'); then
  fail "Alpine / musl libc is unsupported by official D2 standalone binaries. Use a Debian or Ubuntu base image."
fi

# ---------------------------------------------------------------------------
# Architecture validation
# ---------------------------------------------------------------------------
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) fail "Unsupported architecture: $ARCH_RAW. Official D2 releases support amd64 and arm64." ;;
esac

# ---------------------------------------------------------------------------
# Prerequisites (curl, ca-certificates, tar, make)
# ---------------------------------------------------------------------------
apt_install() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "$@"
    rm -rf /var/lib/apt/lists/*
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$@"
    dnf clean all
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y "$@"
    microdnf clean all
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
    yum clean all
  else
    echo "[d2] WARNING: No known package manager found; assuming required tools are present" >&2
  fi
}

PACKAGES_TO_INSTALL=()
command -v curl >/dev/null 2>&1 || PACKAGES_TO_INSTALL+=(curl ca-certificates)
command -v tar >/dev/null 2>&1 || PACKAGES_TO_INSTALL+=(tar)
command -v make >/dev/null 2>&1 || PACKAGES_TO_INSTALL+=(make)

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
  echo "[d2] Installing missing build dependencies: ${PACKAGES_TO_INSTALL[*]}..."
  apt_install "${PACKAGES_TO_INSTALL[@]}"
fi

# ---------------------------------------------------------------------------
# Idempotence check
# ---------------------------------------------------------------------------
SKIP_INSTALL=false
if command -v d2 >/dev/null 2>&1; then
  current="$(d2 version 2>/dev/null || true)"
  if [ "$VERSION" != "latest" ] && printf '%s\n' "$current" | grep -q "${VERSION#v}"; then
    echo "[d2] D2 ${VERSION} already installed: $current. Skipping download."
    SKIP_INSTALL=true
  fi
fi

# ---------------------------------------------------------------------------
# Download and install D2
# ---------------------------------------------------------------------------
if [ "$SKIP_INSTALL" = "false" ]; then
  INSTALL_ARGS=(--prefix "${PREFIX}")
  if [ "${VERSION}" != "latest" ]; then
    INSTALL_ARGS+=(--version "${VERSION}")
  fi

  echo "[d2] Invoking official D2 installer..."
  curl -fsSL https://d2lang.com/install.sh | sh -s -- "${INSTALL_ARGS[@]}"

  # Clean installer cache in /root/.cache/d2 to keep container image minimal
  rm -rf /root/.cache/d2 2>/dev/null || true
fi

# Ensure PREFIX/bin is on PATH or symlinked
if [ ! -f /usr/local/bin/d2 ] && [ -f "${PREFIX}/bin/d2" ]; then
  ln -sf "${PREFIX}/bin/d2" /usr/local/bin/d2
fi

# ---------------------------------------------------------------------------
# Fixed default environment configuration (D2_LAYOUT=tala)
# ---------------------------------------------------------------------------
export D2_LAYOUT=tala

# Export D2_LAYOUT for interactive & login shells
cat <<'EOF' > /etc/profile.d/d2.sh
export D2_LAYOUT=tala
EOF
chmod 0644 /etc/profile.d/d2.sh

# Persist D2_LAYOUT for non-login shells so shells match containerEnv
if [ -f /etc/environment ]; then
  sed -i '/^D2_LAYOUT=/d' /etc/environment 2>/dev/null || true
  echo "D2_LAYOUT=tala" >> /etc/environment
fi

# ---------------------------------------------------------------------------
# Verification & Smoke Test
# ---------------------------------------------------------------------------
command -v d2 >/dev/null 2>&1 || fail "d2 binary not found on PATH after installation"

INSTALLED_VERSION="$(d2 version)"
echo "[d2] Installed version: ${INSTALLED_VERSION}"

echo "[d2] Verifying available layout engines..."
LAYOUTS="$(d2 layout 2>&1)"
echo "${LAYOUTS}"

# TALA is bundled in D2 v0.9.0+; if missing, fail install
if ! echo "${LAYOUTS}" | grep -qi 'tala'; then
  fail "TALA layout engine is missing from installed D2 binary. D2 v0.9.0 or newer is required."
fi

# Smoke test diagram rendering (SVG vector output with default TALA layout)
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT
echo "a -> b: verified" > "${TEST_DIR}/smoke.d2"
d2 "${TEST_DIR}/smoke.d2" "${TEST_DIR}/smoke.svg" >/dev/null 2>&1 || fail "Smoke test diagram compilation failed"

if [ ! -s "${TEST_DIR}/smoke.svg" ]; then
  fail "Smoke test failed: generated SVG is empty"
fi

echo "[d2] D2 feature installation successfully completed (version: ${INSTALLED_VERSION}, default layout: tala)."
