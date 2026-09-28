#!/usr/bin/env bash
# Scenario test for scenarios.json's "default_otel_tui" entry.
set -e
source dev-container-features-test-lib

check "otel-tui binary installed" bash -c "command -v otel-tui"
check "otel-tui-attach wrapper installed" bash -c "command -v otel-tui-attach"
check "start.sh installed" bash -c "test -x /usr/local/share/skill-observability/start.sh"
check "log dir created" bash -c "test -d /var/log/skill-observability"
check "profile.d env file written" bash -c "test -f /etc/profile.d/skill-observability-otel.sh"
check "OTEL_EXPORTER_OTLP_ENDPOINT default is localhost:4318" bash -c \
  "grep -q '127.0.0.1:4318' /etc/profile.d/skill-observability-otel.sh"
check "CLAUDE_CODE_ENABLE_TELEMETRY set (default claudeTelemetry=true)" bash -c \
  "grep -q 'CLAUDE_CODE_ENABLE_TELEMETRY=1' /etc/profile.d/skill-observability-otel.sh"
check "traces beta NOT enabled by default" bash -c \
  "! grep -q 'CLAUDE_CODE_ENHANCED_TELEMETRY_BETA' /etc/profile.d/skill-observability-otel.sh"
check "prompt logging NOT enabled by default" bash -c \
  "! grep -q 'OTEL_LOG_USER_PROMPTS' /etc/profile.d/skill-observability-otel.sh"
check "/etc/environment updated" bash -c "grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT' /etc/environment"
check "otel-tui tmux session is up" bash -c "for i in \$(seq 20); do tmux has-session -t otel-tui 2>/dev/null && exit 0; sleep 0.5; done; exit 1"
check "otel-tui TUI actually renders something in its pane" bash -c \
  "for i in \$(seq 20); do tmux capture-pane -pt otel-tui 2>/dev/null | grep -q . && exit 0; sleep 0.5; done; exit 1"
check "otel-tui accepts OTLP/HTTP JSON traces on :4318" bash -c \
  "for i in \$(seq 30); do curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"resourceSpans\":[]}' http://127.0.0.1:4318/v1/traces && exit 0; sleep 0.5; done; exit 1"
check "otel-tui accepts OTLP/HTTP JSON logs on :4318" bash -c \
  "curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"resourceLogs\":[]}' http://127.0.0.1:4318/v1/logs"
check "otel-tui accepts OTLP/HTTP JSON metrics on :4318" bash -c \
  "curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"resourceMetrics\":[]}' http://127.0.0.1:4318/v1/metrics"

reportResults
