#!/usr/bin/env bash
# Scenario test for scenarios.json's "with_claude_code_plugin_install_attempt"
# entry: a real `claude` CLI is present (via
# ghcr.io/anthropics/devcontainer-features/claude-code), so installPlugin's
# `claude plugin marketplace add borahdev/agent-skills` actually runs. This
# is expected to FAIL until github.com/borahdev/agent-skills is pushed
# publicly, so this test only asserts the install is attempted, logged, and
# retried on next start without ever failing container start (start.sh must
# always reach its final log line and postStartCommand must always exit 0).
set -e
source dev-container-features-test-lib

check "claude CLI on PATH" bash -c "command -v claude"
check "start.sh completed (postStartCommand did not fail container start)" bash -c \
  "grep -q 'skill-observability start.sh done' /var/log/skill-observability/start.log"
check "marketplace add was attempted and logged" bash -c \
  "grep -q 'adding borahdev/agent-skills marketplace' /var/log/skill-observability/start.log"
check "plugin-install.log was created with attempt output" bash -c \
  "test -s /var/log/skill-observability/plugin-install.log"
check "a failed marketplace add is logged as retryable, not fatal" bash -c "
  if [ -f \"\$HOME/.claude/.skill-observability-marketplace-added\" ]; then
    # marketplace add unexpectedly succeeded (e.g. repo already public) - fine, not a failure.
    exit 0
  else
    grep -q 'will retry next start' /var/log/skill-observability/start.log
  fi
"
check "plugin-install.log shows a repo-access failure, not a CLI usage error" bash -c "
  if [ -f \"\$HOME/.claude/.skill-observability-marketplace-added\" ]; then
    exit 0
  else
    ! grep -qi 'unknown command\\|invalid option\\|not a claude command' /var/log/skill-observability/plugin-install.log
  fi
"
check "a second start.sh run re-attempts the install and stays idempotent (exits 0, doesn't double-start otel-tui)" bash -c "
  before=\$(grep -c 'adding borahdev/agent-skills marketplace' /var/log/skill-observability/start.log)
  /usr/local/share/skill-observability/start.sh
  status=\$?
  after=\$(grep -c 'adding borahdev/agent-skills marketplace' /var/log/skill-observability/start.log)
  [ \"\$status\" -eq 0 ] || exit 1
  if [ -f \"\$HOME/.claude/.skill-observability-marketplace-added\" ]; then
    # already succeeded once: no further attempt expected, still must not fail.
    exit 0
  fi
  [ \"\$after\" -gt \"\$before\" ] || exit 1
  grep -q 'otel-tui already running' /var/log/skill-observability/start.log
"

reportResults
