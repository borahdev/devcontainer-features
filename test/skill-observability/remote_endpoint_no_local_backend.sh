#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "no otel-tui binary installed when backend=none" bash -c "! command -v otel-tui"
check "no otel-desktop-viewer binary installed when backend=none" bash -c "! command -v otel-desktop-viewer"
check "OTEL_EXPORTER_OTLP_ENDPOINT points at remote endpoint" bash -c \
  "grep -q 'otlp.example.com' /etc/profile.d/skill-observability-otel.sh"
check "OTEL_EXPORTER_OTLP_HEADERS set from endpointHeaders option" bash -c \
  "grep -q 'x-api-key=dummy-test-key' /etc/profile.d/skill-observability-otel.sh"

reportResults
