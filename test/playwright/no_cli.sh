#!/bin/bash
set -e

source dev-container-features-test-lib

check "playwright-cli is NOT installed" bash -c "! command -v playwright-cli"
check "PLAYWRIGHT_BROWSERS_PATH is set" bash -c "[ \"\$PLAYWRIGHT_BROWSERS_PATH\" = \"/ms-playwright\" ]"
check "/ms-playwright owned by remote user" bash -c "[ \"\$(stat -c %U /ms-playwright)\" = \"\$(whoami)\" ]"
check "a headless screenshot works via node/playwright" bash -c "cd /tmp && timeout 60 npx -y playwright@latest screenshot --channel=chrome about:blank /tmp/check.png >/dev/null 2>&1 && [ -s /tmp/check.png ]"

reportResults
