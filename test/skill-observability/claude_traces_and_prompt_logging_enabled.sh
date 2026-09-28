#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "trace beta enabled" bash -c "grep -q 'CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1' /etc/profile.d/skill-observability-otel.sh"
check "OTEL_TRACES_EXPORTER=otlp set" bash -c "grep -q 'OTEL_TRACES_EXPORTER=otlp' /etc/profile.d/skill-observability-otel.sh"
check "prompt logging enabled" bash -c "grep -q 'OTEL_LOG_USER_PROMPTS=1' /etc/profile.d/skill-observability-otel.sh"
check "tool detail logging enabled" bash -c "grep -q 'OTEL_LOG_TOOL_DETAILS=1' /etc/profile.d/skill-observability-otel.sh"

reportResults
