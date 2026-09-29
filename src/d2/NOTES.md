Declarative diagramming with D2: compiles `.d2` text files into SVG, PNG, and PDF diagrams, bundles layout engines (TALA, Dagre, ELK), and provides first-class VS Code integration.

## Guide

```jsonc
"features": {
  "ghcr.io/borahdev/devcontainer-features/d2:1": {}
}
```

| Option | Default | Notes |
|---|---|---|
| `version` | `latest` | D2 release tag (e.g. `v0.9.0` or `latest`). Pinned releases ensure build reproducibility. |

**Usage**

- **Compile to SVG**:
  ```bash
  d2 input.d2 output.svg
  ```
- **Compile with specific layout engine**:
  ```bash
  d2 --layout elk input.d2 output.svg
  ```
- **Live Preview / Watch mode**:
  ```bash
  d2 --watch input.d2 output.svg
  ```
- **VS Code Live Preview**:
  Open any `.d2` file and press `Ctrl+Shift+D` (or `Cmd+Shift+D` on macOS) to open the interactive live preview. The feature preconfigures formatting on save, 2-space indentation, and the TALA layout engine.

**Overriding the Default Layout**

The feature defaults to TALA (Terrastruct’s AutoLayout Approach). If a project prefers a different default engine (such as ELK), override it directly in the consuming repository's `devcontainer.json` rather than through a feature option:

```jsonc
{
  "features": {
    "ghcr.io/borahdev/devcontainer-features/d2:1": {
      "version": "v0.9.0"
    }
  },
  "containerEnv": {
    "D2_LAYOUT": "elk"
  },
  "customizations": {
    "vscode": {
      "settings": {
        "D2.previewLayout": "elk"
      }
    }
  }
}
```

## Why

- **Zero runtime overhead**: Build-time installation replaces ad-hoc `onCreateCommand: sudo bash .devcontainer/install-d2.sh` scripts, eliminating runtime `sudo` requirements and speeding up container startup.
- **Bundled TALA engine**: Starting with v0.9.0, Terrastruct bundled the TALA layout engine directly into the D2 binary under MPL-2.0. Dagre and ELK are also bundled out of the box, requiring no external daemons or plugin downloads.
- **Preconfigured editor experience**: Automatically provides the `terrastruct.d2` VS Code extension and recommended preview/formatting settings without requiring 20+ lines of snippet boilerplate in each repository's `devcontainer.json`.
- **Multi-architecture**: Supports both `x86_64` (amd64) and `aarch64` (arm64/Apple Silicon) environments with official binaries.

## Quirks

- **Export Formats & Dependencies**:
  - SVG and PNG/GIF/PDF/PPTX export directly from the D2 binary on v0.9.0+; no browser feature required.
  - Pin version to `v0.9.0` or newer if PNG must work without extra dependencies.
- **Layout Override Precedence**:
  - Feature default is TALA via `D2_LAYOUT` + `D2.previewLayout`.
  - CLI `--layout` and diagram `vars.d2-config.layout-engine` still win per D2 precedence.
  - VS Code preview follows `D2.previewLayout`, not the CLI environment alone.
- **Base Image Compatibility**:
  - Official prebuilt binaries require glibc. Use Debian- or Ubuntu-style base images. Alpine/musl is unsupported.
