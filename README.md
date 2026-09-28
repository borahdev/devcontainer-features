# devcontainer-features

Personal, reusable [Dev Container Features](https://containers.dev/implementors/features/), published publicly on GHCR, plus notes for tools that don't need one.

```jsonc
"features": {
  "ghcr.io/borahdev/devcontainer-features/<id>:1": {}
}
```

## Tools

| Tool | Setup | Notes |
|---|---|---|
| Playwright | This repo's Feature: `ghcr.io/borahdev/devcontainer-features/playwright:1` | [src/playwright/NOTES.md](./src/playwright/NOTES.md) |
| Skill observability (OTel viewer for Claude Code) | This repo's Feature: `ghcr.io/borahdev/devcontainer-features/skill-observability:2` | [src/skill-observability/NOTES.md](./src/skill-observability/NOTES.md) |
| pnpm | No Feature: the base image's pnpm switches to the version pinned in `devEngines` | [notes/pnpm.md](./notes/pnpm.md) |
| Bun | Existing Feature: `ghcr.io/devcontainers-extra/features/bun:1` | [notes/bun.md](./notes/bun.md) |

## Layout

- `src/<id>/`: Feature (`devcontainer-feature.json`, `install.sh`, `NOTES.md`). `NOTES.md` is appended to the README generated on release.
- `test/<id>/`: `test.sh`, plus one `<scenario>.sh` per key in `scenarios.json`.
- `notes/`: tools that need no Feature of their own.
