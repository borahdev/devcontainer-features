#!/usr/bin/env bash
# Dev Container Feature: skill-observability
# Runs at image build time (as root) via the devcontainers CLI.
# Installs a local OTLP receiver/viewer and wires OTEL_* env vars so that
# both Claude Code's own telemetry and the agent-skills plugin's hook spans
# (see src/telemetry/otel.ts in borahdev/agent-skills) land in one place
# with zero effort from the developer.
set -euo pipefail

# --- Feature options are exposed as upper-cased env vars by the devcontainers CLI ---
BACKEND="${BACKEND:-otel-tui}"
ENDPOINT="${ENDPOINT:-}"
ENDPOINTHEADERS="${ENDPOINTHEADERS:-}"
UIPORT="${UIPORT:-4319}"
INSTALLPLUGIN="${INSTALLPLUGIN:-true}"
CLAUDETELEMETRY="${CLAUDETELEMETRY:-true}"
CLAUDETRACES="${CLAUDETRACES:-false}"
LOGPROMPTS="${LOGPROMPTS:-false}"

# devcontainers CLI conventions: the non-root user to install "for", and their home.
_REMOTE_USER="${_REMOTE_USER:-root}"
_REMOTE_USER_HOME="${_REMOTE_USER_HOME:-/root}"

SHARE_DIR=/usr/local/share/skill-observability
BIN_DIR=/usr/local/bin
LOG_DIR=/var/log/skill-observability
STATE_DIR=/var/lib/skill-observability

mkdir -p "$SHARE_DIR" "$LOG_DIR" "$STATE_DIR"

echo "[skill-observability] backend=$BACKEND endpoint='${ENDPOINT}' uiPort=$UIPORT installPlugin=$INSTALLPLUGIN claudeTelemetry=$CLAUDETELEMETRY claudeTraces=$CLAUDETRACES logPrompts=$LOGPROMPTS"

# ---------------------------------------------------------------------------
# 1. Base build tools (curl/tar/ca-certificates are needed to fetch binaries;
#    tmux is used to host the otel-tui TUI as a detachable background session)
# ---------------------------------------------------------------------------
apt_install() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "$@"
    rm -rf /var/lib/apt/lists/*
  else
    echo "[skill-observability] WARNING: apt-get not found; assuming $* already present" >&2
  fi
}

MISSING=()
for c in curl tar; do
  command -v "$c" >/dev/null 2>&1 || MISSING+=("$c")
done
command -v tmux >/dev/null 2>&1 || MISSING+=("tmux")
if [ "${#MISSING[@]}" -gt 0 ]; then
  apt_install "${MISSING[@]}"
fi

# ---------------------------------------------------------------------------
# 2. Arch detection
# ---------------------------------------------------------------------------
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) GOARCH=amd64; UNAME_ARCH=x86_64 ;;
  aarch64|arm64) GOARCH=arm64; UNAME_ARCH=arm64 ;;
  *) echo "[skill-observability] WARNING: unsupported arch $ARCH_RAW, skipping local backend install" >&2; GOARCH=""; UNAME_ARCH="" ;;
esac

# ---------------------------------------------------------------------------
# 3. Fetch latest-release binary for the selected backend, matching linux/$GOARCH.
#    Both tools ship gzipped/tar'd single-binary Go releases on GitHub. We query
#    the GitHub Releases API and pick the first asset whose name contains
#    "linux" and the detected arch, falling back gracefully if not found.
# ---------------------------------------------------------------------------
fetch_release_asset() {
  # $1 = owner/repo, $2 = output binary path, $3 = binary name inside archive
  # $4 = required substring for the OS+arch (e.g. "Linux_x86_64" or "linux_amd64"),
  # $5 = optional substring that disqualifies a match (e.g. "homebrew")
  local repo="$1" out="$2" bin_name="$3" arch_pattern="$4" exclude_pattern="${5:-}"
  local api="https://api.github.com/repos/${repo}/releases/latest"
  local tmp
  tmp="$(mktemp -d)"
  if ! curl -fsSL "$api" -o "$tmp/release.json"; then
    echo "[skill-observability] WARNING: could not reach GitHub API for $repo; skipping backend install" >&2
    rm -rf "$tmp"
    return 1
  fi
  local url
  url="$(grep -o '"browser_download_url": *"[^"]*"' "$tmp/release.json" \
    | sed -E 's/.*"(https[^"]+)"/\1/' \
    | grep -F "$arch_pattern" \
    | grep -E '\.(tar\.gz|tgz)$' \
    | { [ -n "$exclude_pattern" ] && grep -v -F "$exclude_pattern" || cat; } \
    | head -n1 || true)"
  if [ -z "$url" ]; then
    echo "[skill-observability] WARNING: no asset matching '$arch_pattern' (.tar.gz) found for $repo; skipping" >&2
    rm -rf "$tmp"
    return 1
  fi
  echo "[skill-observability] downloading $url"
  curl -fsSL "$url" -o "$tmp/asset"
  case "$url" in
    *.tar.gz|*.tgz)
      tar -xzf "$tmp/asset" -C "$tmp"
      local found
      found="$(find "$tmp" -type f -name "$bin_name" | head -n1)"
      [ -n "$found" ] && install -m 0755 "$found" "$out"
      ;;
    *)
      install -m 0755 "$tmp/asset" "$out"
      ;;
  esac
  rm -rf "$tmp"
  [ -x "$out" ]
}

if [ -n "$GOARCH" ] && [ "$BACKEND" != "none" ]; then
  case "$BACKEND" in
    otel-tui)
      # goreleaser asset naming: otel-tui_Linux_x86_64.tar.gz / otel-tui_Linux_arm64.tar.gz
      fetch_release_asset "ymtdzzz/otel-tui" "$BIN_DIR/otel-tui" "otel-tui" "Linux_${UNAME_ARCH}" \
        || echo "[skill-observability] otel-tui install failed; local backend will be unavailable" >&2
      ;;
    otel-desktop-viewer)
      # The prebuilt Linux binary is built against glibc >= 2.38 (verified
      # empirically: it fails with "GLIBC_2.38' not found" on Debian
      # bookworm, which ships 2.36). Check before downloading so we fail
      # with a clear message at build time instead of installing a binary
      # that silently won't start.
      GLIBC_VER="$(ldd --version 2>/dev/null | head -n1 | grep -o '[0-9]\+\.[0-9]\+$' || echo 0.0)"
      GLIBC_OK="$(awk -v v="$GLIBC_VER" 'BEGIN{split(v,a,"."); print (a[1]>2 || (a[1]==2 && a[2]>=38)) ? "1":"0"}')"
      if [ "$GLIBC_OK" != "1" ]; then
        echo "[skill-observability] WARNING: otel-desktop-viewer needs glibc >= 2.38, this image has ${GLIBC_VER}." >&2
        echo "[skill-observability] WARNING: use a newer base image (e.g. ubuntu:24.04 / debian:trixie) or set backend=otel-tui. Skipping local backend install." >&2
      else
        # goreleaser asset naming: otel-desktop-viewer_linux_amd64.tar.gz (also
        # ships _homebrew_linux_amd64.tar.gz, .deb, .rpm variants we must not match)
        fetch_release_asset "CtrlSpice/otel-desktop-viewer" "$BIN_DIR/otel-desktop-viewer" "otel-desktop-viewer" "linux_${GOARCH}" "homebrew" \
          || echo "[skill-observability] otel-desktop-viewer install failed; local backend will be unavailable" >&2
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# 4. Runtime start script (idempotent; invoked by postStartCommand on every
#    container start, not just image build, since the container's PID/network
#    namespace is fresh each start).
# ---------------------------------------------------------------------------
cat > "$SHARE_DIR/start.sh" <<'STARTSCRIPT'
#!/usr/bin/env bash
# Idempotently (re)starts the local OTLP backend and, if requested, installs
# the agent-skills plugin. Safe to run on every container start.
set -uo pipefail

BACKEND="__BACKEND__"
UIPORT="__UIPORT__"
INSTALLPLUGIN="__INSTALLPLUGIN__"
LOG_DIR="/var/log/skill-observability"
mkdir -p "$LOG_DIR"

log() { echo "[skill-observability $(date -u +%FT%TZ)] $*" | tee -a "$LOG_DIR/start.log" >&2; }

start_otel_tui() {
  command -v otel-tui >/dev/null 2>&1 || { log "otel-tui binary not installed, skipping"; return; }
  command -v tmux >/dev/null 2>&1 || { log "tmux not installed, cannot host otel-tui, skipping"; return; }
  if tmux has-session -t otel-tui 2>/dev/null; then
    log "otel-tui already running (tmux session 'otel-tui')"
    return
  fi
  log "starting otel-tui in tmux session 'otel-tui' (OTLP HTTP on :4318)"
  # Do NOT redirect otel-tui's own stdout to a file: it IS the TUI, and
  # redirecting it here would leave `otel-tui-attach` looking at a blank
  # pane. Use its own --debug-log flag (writes to /tmp/otel-tui.log) for
  # diagnostics instead.
  tmux new-session -d -s otel-tui "otel-tui --debug-log"
}

start_otel_desktop_viewer() {
  command -v otel-desktop-viewer >/dev/null 2>&1 || { log "otel-desktop-viewer binary not installed, skipping"; return; }
  if pgrep -f "otel-desktop-viewer" >/dev/null 2>&1; then
    log "otel-desktop-viewer already running"
    return
  fi
  log "starting otel-desktop-viewer (UI on :$UIPORT, OTLP HTTP on :4318)"
  mkdir -p /var/lib/skill-observability 2>/dev/null || true
  # --host 0.0.0.0 so the port is reachable for VS Code port-forwarding (its
  # default is localhost-only); --open-browser=false because there is no
  # browser inside the container; --db persists traces/logs/metrics across
  # restarts in the feature's named volume instead of the default in-memory
  # store.
  nohup otel-desktop-viewer \
    --host 0.0.0.0 \
    --browser-port "$UIPORT" \
    --open-browser=false \
    --db /var/lib/skill-observability/otel-desktop-viewer.duckdb \
    >> "$LOG_DIR/otel-desktop-viewer.log" 2>&1 &
  disown || true
}

case "$BACKEND" in
  otel-tui) start_otel_tui ;;
  otel-desktop-viewer) start_otel_desktop_viewer ;;
  none) log "backend=none, not starting a local OTLP receiver" ;;
  *) log "unknown backend '$BACKEND'" ;;
esac

if [ "$INSTALLPLUGIN" = "true" ]; then
  if command -v claude >/dev/null 2>&1; then
    MARKETPLACE_MARKER="$HOME/.claude/.skill-observability-marketplace-added"
    PLUGIN_MARKER="$HOME/.claude/.skill-observability-plugin-installed"
    mkdir -p "$HOME/.claude" 2>/dev/null || true
    if [ ! -f "$MARKETPLACE_MARKER" ]; then
      log "adding borahdev/agent-skills marketplace (registers as 'borahdev')"
      if claude plugin marketplace add https://github.com/borahdev/agent-skills.git >> "$LOG_DIR/plugin-install.log" 2>&1; then
        touch "$MARKETPLACE_MARKER" 2>/dev/null || true
      else
        log "marketplace add failed (see $LOG_DIR/plugin-install.log); will retry next start"
      fi
    fi
    if [ -f "$MARKETPLACE_MARKER" ] && [ ! -f "$PLUGIN_MARKER" ]; then
      log "installing agent-skills plugin (user scope, default)"
      if claude plugin install agent-skills@borahdev >> "$LOG_DIR/plugin-install.log" 2>&1; then
        touch "$PLUGIN_MARKER" 2>/dev/null || true
      else
        log "plugin install failed (see $LOG_DIR/plugin-install.log); will retry next start"
      fi
    fi
  else
    log "installPlugin=true but 'claude' CLI not on PATH yet; skipping (will retry next start)"
  fi
fi

log "skill-observability start.sh done"
STARTSCRIPT

sed -i "s|__BACKEND__|${BACKEND}|" "$SHARE_DIR/start.sh"
sed -i "s|__UIPORT__|${UIPORT}|" "$SHARE_DIR/start.sh"
sed -i "s|__INSTALLPLUGIN__|${INSTALLPLUGIN}|" "$SHARE_DIR/start.sh"
chmod 0755 "$SHARE_DIR/start.sh"

# Convenience wrapper to attach to the otel-tui TUI from any shell.
cat > "$BIN_DIR/otel-tui-attach" <<'ATTACHSCRIPT'
#!/usr/bin/env bash
exec tmux attach -t otel-tui
ATTACHSCRIPT
chmod 0755 "$BIN_DIR/otel-tui-attach"

# ---------------------------------------------------------------------------
# 5. Resolve and write OTEL_* / CLAUDE_CODE_* env vars.
#    containerEnv in devcontainer-feature.json only supports static string
#    values (no ${options:...} interpolation is documented in the spec), so
#    it cannot express the resolved `endpoint`/`endpointHeaders` values. We
#    write a concrete file to /etc/profile.d instead. This is the primary,
#    *documented* channel: the devcontainers CLI / VS Code's `userEnvProbe`
#    setting defaults to "loginInteractiveShell", which spawns a login+
#    interactive shell to capture env vars (sourcing /etc/profile -> profile.d
#    -> /etc/bash.bashrc) and applies the result to every terminal it opens
#    and to postStartCommand/postAttachCommand it runs
#    (https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainerjson-reference.md).
#    Claude Code, started from such a terminal, and the hook subprocesses it
#    spawns, inherit this as ordinary process environment.
#
#    We ALSO append to /etc/environment as a defensive fallback for tools
#    that read it directly, but this is NOT reliable for a plain
#    `docker exec` (no `-l`) into the container: PAM's pam_env only runs for
#    a real login session (sshd, `login`), and neither `docker exec` nor
#    `docker exec -l` invokes PAM, so /etc/environment alone is empirically
#    NOT picked up by either -- verified with `docker exec` against
#    mcr.microsoft.com/devcontainers/base:bookworm. If a workflow bypasses
#    the devcontainers CLI/VS Code entirely (raw `docker exec`), only a
#    login shell (`bash -l`, which sources /etc/profile.d) will see these
#    vars.
# ---------------------------------------------------------------------------
if [ -n "$ENDPOINT" ]; then
  RESOLVED_ENDPOINT="$ENDPOINT"
else
  RESOLVED_ENDPOINT="http://127.0.0.1:4318"
fi

ENV_FILE="/etc/profile.d/skill-observability-otel.sh"
{
  echo "# Generated by the skill-observability dev container feature. Do not edit by hand."
  echo "export OTEL_EXPORTER_OTLP_ENDPOINT=\"${RESOLVED_ENDPOINT}\""
  echo "export OTEL_SERVICE_NAME=\"agent-skills\""
  echo "export OTEL_RESOURCE_ATTRIBUTES=\"deployment.environment=devcontainer\""
  if [ -n "$ENDPOINTHEADERS" ]; then
    echo "export OTEL_EXPORTER_OTLP_HEADERS=\"${ENDPOINTHEADERS}\""
  fi
  if [ "$CLAUDETELEMETRY" = "true" ]; then
    echo "export CLAUDE_CODE_ENABLE_TELEMETRY=1"
    echo "export OTEL_METRICS_EXPORTER=otlp"
    echo "export OTEL_LOGS_EXPORTER=otlp"
    echo "export OTEL_EXPORTER_OTLP_PROTOCOL=http/json"
    if [ "$CLAUDETRACES" = "true" ]; then
      echo "export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1"
      echo "export OTEL_TRACES_EXPORTER=otlp"
    fi
    if [ "$LOGPROMPTS" = "true" ]; then
      echo "export OTEL_LOG_USER_PROMPTS=1"
      echo "export OTEL_LOG_TOOL_DETAILS=1"
    fi
  fi
} > "$ENV_FILE"
chmod 0644 "$ENV_FILE"

# Also append to /etc/environment (KEY=VALUE, no `export`, no expansion) for
# non-login-shell inheritance. Guard against duplicate entries on rebuild.
{
  grep -q '^OTEL_EXPORTER_OTLP_ENDPOINT=' /etc/environment 2>/dev/null && \
    sed -i '/^OTEL_EXPORTER_OTLP_ENDPOINT=/d;/^OTEL_SERVICE_NAME=/d;/^OTEL_RESOURCE_ATTRIBUTES=/d;/^OTEL_EXPORTER_OTLP_HEADERS=/d;/^CLAUDE_CODE_ENABLE_TELEMETRY=/d;/^OTEL_METRICS_EXPORTER=/d;/^OTEL_LOGS_EXPORTER=/d;/^OTEL_EXPORTER_OTLP_PROTOCOL=/d;/^CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=/d;/^OTEL_TRACES_EXPORTER=/d;/^OTEL_LOG_USER_PROMPTS=/d;/^OTEL_LOG_TOOL_DETAILS=/d' /etc/environment
  true
}
{
  echo "OTEL_EXPORTER_OTLP_ENDPOINT=${RESOLVED_ENDPOINT}"
  echo "OTEL_SERVICE_NAME=agent-skills"
  echo "OTEL_RESOURCE_ATTRIBUTES=deployment.environment=devcontainer"
  [ -n "$ENDPOINTHEADERS" ] && echo "OTEL_EXPORTER_OTLP_HEADERS=${ENDPOINTHEADERS}"
  if [ "$CLAUDETELEMETRY" = "true" ]; then
    echo "CLAUDE_CODE_ENABLE_TELEMETRY=1"
    echo "OTEL_METRICS_EXPORTER=otlp"
    echo "OTEL_LOGS_EXPORTER=otlp"
    echo "OTEL_EXPORTER_OTLP_PROTOCOL=http/json"
    if [ "$CLAUDETRACES" = "true" ]; then
      echo "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1"
      echo "OTEL_TRACES_EXPORTER=otlp"
    fi
    if [ "$LOGPROMPTS" = "true" ]; then
      echo "OTEL_LOG_USER_PROMPTS=1"
      echo "OTEL_LOG_TOOL_DETAILS=1"
    fi
  fi
} >> /etc/environment

log_owner_chown() {
  if [ "$_REMOTE_USER" != "root" ] && id "$_REMOTE_USER" >/dev/null 2>&1; then
    chown -R "$_REMOTE_USER" "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
  fi
}
log_owner_chown

echo "[skill-observability] install.sh complete"
