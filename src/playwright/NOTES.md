Browser checks for a coding agent (Claude Code): `@playwright/cli` for live, agent-driven checks, plus a matching browser your project's own `@playwright/test` can reuse.

## Guide

```jsonc
"features": {
  "ghcr.io/borahdev/devcontainer-features/playwright:1": {}
}
```

| Option | Default | Notes |
|---|---|---|
| `browser` | `auto` | `chrome` on x64, `chromium` on arm64 (Playwright can't install Chrome there); `none` skips browser install |
| `cli` | `true` | installs `@playwright/cli` (`playwright-cli` on PATH) |
| `cliVersion` | `0.1.21` | `@playwright/cli` version (pinned, not `latest`, for reproducible builds) |

**Which tool when**
- **CLI** (`playwright-cli`) — the agent's live checks: low context, writes snapshots/screenshots to `.playwright-cli/` in cwd.
- **`@playwright/test` specs** — saved, repeatable checks; agent or CI runs `pnpm exec playwright test`. Promote a worthwhile CLI check into a spec once it's proven useful.
- **MCP** — skip unless you specifically want tool-call based control; headed by default (pass `--headless`) and heavier on context than the CLI.

**Per-project steps**
- `playwright-cli install --skills` (in `postCreate`, or commit the generated `.claude/skills` entry).
- gitignore `.playwright-cli/`, `playwright-report/`, `test-results/`.
- For `@playwright/test` specs, either `use: { channel: 'chrome' }` (x64) or run `pnpm exec playwright install chromium` in `postCreate` (version-matched to your project's Playwright, lands in `/ms-playwright`).
- Use `webServer` in `playwright.config` to start your api/web servers before tests run.

**Responsive checks**: CLI — `playwright-cli resize <w> <h>` then `playwright-cli screenshot`. Specs — one project per device in `playwright.config`, assert with `toHaveScreenshot()`.

**Viewing output**: the workspace is a bind mount, so `.playwright-cli/*.png` and `playwright-report/` are on the host immediately — no container needed to view them, and the agent can read the PNGs directly. For specs, `pnpm exec playwright show-report --host 0.0.0.0` serves the HTML report (port 9323); traces via `pnpm exec playwright show-trace <trace.zip>` or trace.playwright.dev. Anything outside the workspace (`/ms-playwright`, `/tmp`) isn't on the host. There's no live headed browser in a devcontainer (no display).

**API-only e2e** (NestJS + Jest/Vitest + supertest) needs no browser and not this Feature. Full-stack e2e (web calling API) does.

## Why

- Chrome is shared by every Playwright package (CLI, MCP, `@playwright/test`) on the machine, so x64 needs only one browser install. On arm64 Playwright can't install Chrome, so it falls back to Chromium.
- Browser/dep installs need root, so build time (`install.sh`) is the only place to do them — not `postCreate`.
- Browsers live in `/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`) instead of the default cache dir, because `install.sh` runs as root at build time (default would be `/root/.cache`, unreachable for the remote user) — a fixed shared path also lets a later `pnpm exec playwright install chromium` in the project reuse the same location.

## Quirks

- `playwright-cli` defaults to the `chrome` channel: `/opt/google/chrome/chrome`, which ignores `PLAYWRIGHT_BROWSERS_PATH`.
- The Feature writes `~/.playwright/cli.config.json` with `--no-sandbox`, plus `browserName: chromium` when `browser: chromium`. A project's `.playwright/cli.config.json` overrides it. Without `--no-sandbox`, container seccomp blocks Chrome's sandbox (`Zygote process exited prematurely`). `@playwright/test` needs nothing, because it disables the sandbox by default.
- `playwright-cli open` keeps a browser daemon running until `playwright-cli close`. In scripts, pair them (`trap ... EXIT`) and wrap calls in `timeout`, or the shell never returns.
- The CLI and MCP pin a prerelease Playwright (`1.64.0-alpha`), which won't match your `@playwright/test`. So expect a separate Chromium, unless both use `channel: 'chrome'`.
- arm64: Google ships Chrome for Linux arm64, but `playwright install chrome` refuses to install it, so `auto` uses Chromium there.
- Responsive checks: `playwright-cli resize <w> <h>`, then `screenshot`.
- `browser: none`: `playwright-cli` errors until a browser is installed.
