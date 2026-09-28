# Bun

Use the existing Feature. There's no reason to build one here.

## Guide

```jsonc
"features": {
  "ghcr.io/devcontainers-extra/features/bun:1": {}   // or { "version": "1.4.2" }
}
```

| Situation | Do |
|---|---|
| Update | Rebuild the container (installs latest), or run `sudo bun upgrade` in between |
| Pin | Set `"version": "x.y.z"` |

## Why

- It installs `bun` and `bunx` into `/usr/local/bin`, which is on PATH for every shell, including the non-interactive ones Claude Code hooks run in. The official `curl | bash` installer only edits `~/.bashrc`.
- An unpinned version is fine when Bun is only for tooling, such as skill and hook scripts. pnpm still manages the project's packages.

## Quirks

- Bun can't pin its own version from the project the way pnpm does. It has no `devEngines` support ([#26512](https://github.com/oven-sh/bun/issues/26512)), no `.bun-version` support, and `bun upgrade` only goes to the latest release.
- `bun upgrade` needs `sudo` because `/usr/local/bin` is owned by root.
- It's community-maintained. It looks up releases through the GitHub API, which allows 60 requests an hour without a login, so a build can fail on the rate limit. Retrying later fixes it.
- On x64 it installs Bun's `baseline` build, which is made for broader CPU support.
