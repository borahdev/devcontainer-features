#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "otel-desktop-viewer binary installed" bash -c "command -v otel-desktop-viewer"
check "otel-tui binary NOT installed for this backend" bash -c "! command -v otel-tui"
check "otel-desktop-viewer process running" bash -c \
  "for i in \$(seq 30); do pgrep -f otel-desktop-viewer >/dev/null && exit 0; sleep 0.5; done; exit 1"
check "otel-desktop-viewer web UI answers on :4319" bash -c \
  "for i in \$(seq 30); do curl -sf -o /dev/null http://127.0.0.1:4319/ && exit 0; sleep 0.5; done; exit 1"
check "otel-desktop-viewer accepts OTLP/HTTP JSON traces on :4318" bash -c \
  "for i in \$(seq 30); do curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"resourceSpans\":[]}' http://127.0.0.1:4318/v1/traces && exit 0; sleep 0.5; done; exit 1"
check "otel-desktop-viewer accepts OTLP/HTTP JSON logs on :4318" bash -c \
  "curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"resourceLogs\":[]}' http://127.0.0.1:4318/v1/logs"
check "otel-desktop-viewer accepts OTLP/HTTP JSON metrics on :4318" bash -c \
  "curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"resourceMetrics\":[]}' http://127.0.0.1:4318/v1/metrics"
check "DuckDB persistence file created" bash -c \
  "for i in \$(seq 20); do test -f /var/lib/skill-observability/otel-desktop-viewer.duckdb && exit 0; sleep 0.5; done; exit 1"

reportResults
