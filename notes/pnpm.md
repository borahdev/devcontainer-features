# pnpm

pnpm (11+) switches itself to the version pinned in `package.json`. 
Any recent pnpm on PATH is enough.

## Guide

```jsonc
// package.json - single source of truth
"devEngines": {
  "packageManager": { "name": "pnpm", "version": "12.6.0", "onFail": "download" }
}
```

| Situation | Do |
|---|---|
| Update pnpm | Bump `devEngines` version - `pnpm install` - bump CI `version:` - commit together. Devcontainer: nothing, no rebuild. |
| Base image has no pnpm | `"ghcr.io/devcontainers/features/node:1": { "pnpmVersion": "latest" }`, or `npm i -g pnpm`. |
| Base image has another pnpm 11+ | Nothing - it switches to the pin. |
| Want minor updates automatically | `"version": "^12.6.0"`; resolved version is stored in `pnpm-lock.yaml`. |
| Store | `containerEnv: { "PNPM_CONFIG_STORE_DIR": "/workspaces/<repo>/.pnpm-store" }` + gitignore `.pnpm-store/`. |
| `pnpm add -g` (optional) | `containerEnv: { "PNPM_HOME": "/home/node/.local/share/pnpm" }` + `remoteEnv: { "PATH": "${containerEnv:PATH}:/home/node/.local/share/pnpm" }`. |

No PATH setup is needed for pnpm itself or its version switching — both work with just the base image's pnpm.

## Why

- **Keep the pin**: every environment resolves the same version; upgrades are reviewable commits, not base-image surprises.
- **No corepack**: removed from Node 25+. Old bundled corepack "installs" pnpm 12 but it then crashes. pnpm's docs don't mention it. Also removes the root-vs-remoteUser EACCES dance.
- **No store config needed**: pnpm hardlinks store - `node_modules` only on the same filesystem, and handles that itself — when `~/.local/share/pnpm/store` is on a different fs than the project (container home vs host bind mount), it puts the store at the root of the project's mount instead (e.g. `/workspaces/.pnpm-store`). Hardlinks work, store lives on the host and survives rebuilds.
- **Still set `PNPM_CONFIG_STORE_DIR` per repo**: that auto root depends on the mount. When a parent dir is mounted (e.g. `../..:/workspaces`), the store lands in the host's parent dir (`~/Projects/.pnpm-store`), shared by every sibling project's container — owned by nobody's `.gitignore`/cleanup, mixed uids across containers, one project's installs feeding another's. Per-repo is isolated, deterministic, and deleted with the repo; cost is only less cross-project dedup. Use env — not `pnpm-workspace.yaml`, where a container-only path breaks CI. A named volume doesn't help — different fs.
- **No `PNPM_HOME`**: only `pnpm add -g` needs it. Nothing else does, including version switching.

## Quirks

- pnpm =< 10 ignores `devEngines` silently (10 honors legacy `packageManager` only).
- Running `npx` from inside a pinned repo fails on the host (`EBADDEVENGINES`) - run it from elsewhere.
- pnpm 11 config: `.npmrc` is auth/registry only; other settings go in `pnpm-workspace.yaml`, `~/.config/pnpm/config.yaml`, or `pnpm_config_*` env vars (uppercase also works).
- "Update available" banner after install is just a notice.
- pnpm 12: `pnpm setup` / `self-update` / global changes fail under `sudo` — run them as the remote user.

Refs: [pnpm 11.0](https://pnpm.io/blog/releases/11.0), [store](https://pnpm.io/settings/store), [installation](https://pnpm.io/installation).
