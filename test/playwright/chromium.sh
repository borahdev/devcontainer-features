#!/bin/bash
set -e

source dev-container-features-test-lib

check "playwright-cli on PATH" bash -c "command -v playwright-cli"
check "PLAYWRIGHT_BROWSERS_PATH is set" bash -c "[ \"\$PLAYWRIGHT_BROWSERS_PATH\" = \"/ms-playwright\" ]"
check "/ms-playwright writable by remote user" bash -c "[ -w /ms-playwright ]"
check "chromium is the default browser" bash -c "[ -f \"\$HOME/.playwright/cli.config.json\" ] && grep -q chromium \"\$HOME/.playwright/cli.config.json\""
check "headless screenshot works" bash -c "
    cd /tmp
    trap 'playwright-cli close >/dev/null 2>&1' EXIT
    timeout 60 playwright-cli open about:blank >/dev/null 2>&1 &&
    timeout 60 playwright-cli screenshot --filename=/tmp/check.png >/dev/null 2>&1 &&
    [ -s /tmp/check.png ]
"

reportResults
