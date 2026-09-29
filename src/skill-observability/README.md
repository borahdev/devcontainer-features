
# Skill Observability (skill-observability)

Zero-effort local OpenTelemetry viewing for Claude Code plugin/skill runs and Claude Code's own telemetry. Starts a lightweight in-container OTLP receiver+viewer and wires OTEL_* env vars so Claude Code's telemetry (and any plugin/skill hook spans it or your project emits) export to it.

## Example Usage

```json
"features": {
    "ghcr.io/borahdev/devcontainer-features/skill-observability:2": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| backend | Which local OTLP receiver/viewer to run inside the container. 'otel-tui' is a terminal UI (no forwarded port needed to view it, attach with 'otel-tui-attach'); works on any glibc/Debian/Ubuntu base image. 'otel-desktop-viewer' serves a web UI on uiPort, but its prebuilt Linux binary requires glibc >= 2.38 (e.g. Ubuntu 24.04/'noble', Debian 'trixie'); it will fail to start on glibc 2.36 images such as the common debian:bookworm-based devcontainer base images. 'none' skips installing any local backend (use with 'endpoint' for a remote/cloud backend). | string | otel-tui |
| endpoint | Remote OTLP/HTTP endpoint base URL (e.g. https://otlp-gateway.example.com). When set, this takes priority over the local backend: OTEL_EXPORTER_OTLP_ENDPOINT is set to this value and 'backend' is ignored for endpoint purposes (the local backend, if any, still starts and can be pointed at manually). Leave empty to use the local backend on 127.0.0.1. | string | - |
| endpointHeaders | Value for OTEL_EXPORTER_OTLP_HEADERS when using a remote endpoint, e.g. 'Authorization=Bearer xxxx,x-honeycomb-team=xxxx'. Prefer passing this via remoteEnv/localEnv in devcontainer.json rather than baking it into the image; this option exists for convenience when the value is not a secret (e.g. a local collector). | string | - |
| uiPort | Port for the local backend's web UI (only used by otel-desktop-viewer). The OTLP HTTP receiver itself always listens on 4318. | string | 4319 |
| claudeTelemetry | Set CLAUDE_CODE_ENABLE_TELEMETRY=1 plus OTEL_METRICS_EXPORTER=otlp and OTEL_LOGS_EXPORTER=otlp so Claude Code's own metrics and events flow to the local backend. | boolean | true |
| claudeTraces | Also enable Claude Code's beta trace export (CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1, OTEL_TRACES_EXPORTER=otlp). Off by default because it is a separate beta signal from Claude Code's default metrics/logs. | boolean | false |
| logPrompts | Set OTEL_LOG_USER_PROMPTS=1 (and OTEL_LOG_TOOL_DETAILS=1) so Claude Code's own OTel events include prompt text and tool parameters. Off by default for privacy. | boolean | false |

Zero-effort local OpenTelemetry viewing for Claude Code inside a dev container: an in-container OTLP receiver + viewer, with `OTEL_*` env vars wired for Claude Code's own telemetry (and any plugin/skill hook spans your project emits, if it exports OTel the same way).

## Guide

```jsonc
"features": {
  "ghcr.io/anthropics/devcontainer-features/claude-code:1": {},
  "ghcr.io/borahdev/devcontainer-features/skill-observability:2": {}
}
```

| Option | Default | Notes |
|---|---|---|
| `backend` | `otel-tui` | `otel-tui` \| `otel-desktop-viewer` \| `none`. `none` skips the local backend (remote/other-machine mode, use with `endpoint`). |
| `endpoint` | `""` | Remote OTLP/HTTP base URL. When set, `OTEL_EXPORTER_OTLP_ENDPOINT` points here instead of `http://127.0.0.1:4318`. |
| `endpointHeaders` | `""` | Value for `OTEL_EXPORTER_OTLP_HEADERS`, e.g. `Authorization=Bearer xxxx`. Prefer `remoteEnv`/`localEnv` (see below) when the value is a secret. |
| `uiPort` | `"4319"` | `otel-desktop-viewer`'s web UI port (unused by `otel-tui`, a TUI). The OTLP HTTP receiver itself always listens on `4318`. |
| `claudeTelemetry` | `true` | Sets `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp` so Claude Code's own telemetry lands in the local backend. |
| `claudeTraces` | `false` | Also enables Claude Code's beta trace export (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`, `OTEL_TRACES_EXPORTER=otlp`) — a separate beta signal from Claude Code's default metrics/logs. |
| `logPrompts` | `false` | Includes prompt text and tool parameters in Claude Code's own OTel events (`OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_TOOL_DETAILS=1`). Off by default for privacy.

**Viewing traces**
- `otel-tui` (default): `otel-tui-attach` from any shell attaches to the backend's `tmux` session; detach with `Ctrl-b d` without stopping it.
- `otel-desktop-viewer`: open `http://localhost:<uiPort>` (VS Code offers to forward the port automatically, or forward it manually).

Logs for the backend: `/var/log/skill-observability/`.

**Remote / other-machine mode** — set `backend: "none"` and `endpoint` to a reachable collector URL; pass any secret header via `remoteEnv` (resolved from the *local* environment, never baked into the image):

```jsonc
{
  "remoteEnv": {
    "OTEL_EXPORTER_OTLP_HEADERS": "${localEnv:OTEL_HEADERS_SECRET}"
  },
  "features": {
    "ghcr.io/borahdev/devcontainer-features/skill-observability:2": {
      "backend": "none",
      "endpoint": "https://otlp-gateway.example.com"
    }
  }
}
```

`remoteEnv` is resolved when the devcontainers CLI attaches a process to the container, not baked into the image, so the secret never lands in a committed `devcontainer.json` or an image layer.

## Why

- **`otel-tui` is the default**: no forwarded port needed (fits a terminal-first workflow), supports traces/logs/metrics, and its binary runs cleanly on the standard `debian:bookworm`-based devcontainer base image, unlike `otel-desktop-viewer`.
- **`otel-desktop-viewer` needs glibc >= 2.38**: its prebuilt Linux binary fails with `` GLIBC_2.38' not found `` on Debian bookworm (glibc 2.36) — the base of `mcr.microsoft.com/devcontainers/base:bookworm`, a very common devcontainer image. `install.sh` checks `glibc` before downloading and skips cleanly with a warning instead of installing a binary that silently won't start; use Ubuntu 24.04/"noble" or Debian "trixie" or newer, or leave `backend` at `otel-tui`.
- **`grafana/otel-lgtm` was considered and rejected**: it bundles Loki+Grafana+Tempo+Mimir+Collector as one Docker image, which needs Docker (or Docker-in-Docker) to run — not usable as an in-container process the way `otel-tui`/`otel-desktop-viewer` are.
- **Env vars go through `/etc/profile.d`, not just `containerEnv`**: `containerEnv` in `devcontainer-feature.json` only supports static string values (no `${options:...}` interpolation), so it can't express the resolved `endpoint`/`endpointHeaders` values. A generated `/etc/profile.d/skill-observability-otel.sh` is the primary, documented channel — the devcontainers CLI / VS Code's `userEnvProbe` (default `loginInteractiveShell`) sources it into every terminal and into `postStartCommand`/`postAttachCommand`. `/etc/environment` is also written as a defensive fallback, but is **not** reliable for a plain `docker exec` (no `-l`): PAM's `pam_env` only runs for a real login session, so only a login shell (`bash -l`) reliably sees these vars outside the devcontainers CLI/VS Code.
- **The local backend is started from `postStartCommand`, not build time**: the container's PID/network namespace is fresh on every start, so the backend must be (re)started idempotently each time, not just once at image build.

## Quirks

- `otel-desktop-viewer`'s in-memory store is ephemeral by default; this feature passes `--db /var/lib/skill-observability/otel-desktop-viewer.duckdb` (backed by the feature's own named volume) so traces/logs/metrics persist across container restarts.
- `logPrompts` only affects Claude Code's own OTel events.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/borahdev/devcontainer-features/blob/main/src/skill-observability/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
