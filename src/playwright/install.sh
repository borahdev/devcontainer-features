#!/usr/bin/env bash
set -e

BROWSER="${BROWSER:-auto}"
CLI="${CLI:-true}"
CLIVERSION="${CLIVERSION:-latest}"
_REMOTE_USER="${_REMOTE_USER:-node}"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: node/npm not found. This feature requires a Node.js base image or the node Feature to run first (installsAfter should already ensure this)." >&2
    exit 1
fi

mkdir -p /ms-playwright
chown -R "${_REMOTE_USER}:" /ms-playwright

# Resolve 'auto': chrome has no Linux arm64 build, so fall back to chromium there.
if [ "${BROWSER}" = "auto" ]; then
    arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "${arch}" in
        amd64|x86_64) BROWSER="chrome" ;;
        *) BROWSER="chromium" ;;
    esac
fi

echo "playwright feature: browser=${BROWSER} cli=${CLI} cliVersion=${CLIVERSION}"

PW_BIN=""

if [ "${CLI}" = "true" ]; then
    npm install -g "@playwright/cli@${CLIVERSION}"
    # Make sure playwright-cli is on PATH for every (non-interactive) shell.
    ln -sf "$(npm root -g)/@playwright/cli/playwright-cli.js" /usr/local/bin/playwright-cli
    chmod +x /usr/local/bin/playwright-cli

    # Use the CLI's own bundled playwright so browser revisions match what the CLI drives.
    PW_CLI_JS="$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js"
    if [ -f "${PW_CLI_JS}" ]; then
        PW_BIN="node ${PW_CLI_JS}"
    else
        echo "ERROR: could not find playwright/cli.js under @playwright/cli's node_modules" >&2
        exit 1
    fi
fi

# Write a global CLI config (the project's own .playwright/cli.config.json still
# overrides it) for two reasons:
# - Containers (this one included) commonly run with a seccomp profile that blocks
#   the unprivileged user namespaces Chrome's sandbox needs, so the browser's
#   zygote process dies on launch unless launched with --no-sandbox.
# - playwright-cli defaults to the 'chrome' channel; on arm64 (or browser=chromium
#   explicitly) that default is wrong, so point it at chromium instead.
if [ "${CLI}" = "true" ] && [ "${BROWSER}" != "none" ]; then
    remote_home="$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)"
    remote_home="${remote_home:-/home/${_REMOTE_USER}}"
    mkdir -p "${remote_home}/.playwright"
    if [ "${BROWSER}" = "chromium" ]; then
        cat > "${remote_home}/.playwright/cli.config.json" <<'EOF'
{
  "browser": {
    "browserName": "chromium",
    "launchOptions": {
      "args": ["--no-sandbox"]
    }
  }
}
EOF
    else
        cat > "${remote_home}/.playwright/cli.config.json" <<'EOF'
{
  "browser": {
    "launchOptions": {
      "args": ["--no-sandbox"]
    }
  }
}
EOF
    fi
    chown -R "${_REMOTE_USER}:" "${remote_home}/.playwright"
fi

case "${BROWSER}" in
    none)
        echo "playwright feature: browser=none, skipping browser install"
        ;;
    chrome)
        if [ -z "${PW_BIN}" ]; then
            npx -y playwright@latest install-deps chrome
            npx -y playwright@latest install chrome
        else
            ${PW_BIN} install-deps chrome
            ${PW_BIN} install chrome
        fi
        ;;
    chromium)
        if [ -z "${PW_BIN}" ]; then
            npx -y playwright@latest install-deps chromium
            PLAYWRIGHT_BROWSERS_PATH=/ms-playwright npx -y playwright@latest install chromium
        else
            ${PW_BIN} install-deps chromium
            PLAYWRIGHT_BROWSERS_PATH=/ms-playwright ${PW_BIN} install chromium
        fi
        chown -R "${_REMOTE_USER}:" /ms-playwright
        ;;
    *)
        echo "ERROR: unknown browser option '${BROWSER}' (expected auto, chrome, chromium, or none)" >&2
        exit 1
        ;;
esac

# The remote user's UID can be remapped after build (updateRemoteUserUID), which
# orphans the chown above. Keep the browsers dir writable for whoever it becomes.
chmod -R a+rwX /ms-playwright

rm -rf /var/lib/apt/lists/*

echo "Done installing playwright feature."
