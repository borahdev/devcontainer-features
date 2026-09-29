#!/bin/bash
set -e

source dev-container-features-test-lib

check "d2 binary on PATH" bash -c "command -v d2"
check "d2 version runs" bash -c "d2 version"
check "d2 layouts include tala, dagre, elk" bash -c "
  layouts=\"\$(d2 layout 2>&1)\"
  echo \"\$layouts\" | grep -qi 'tala' && \
  echo \"\$layouts\" | grep -qi 'dagre' && \
  echo \"\$layouts\" | grep -qi 'elk'
"
check "default D2_LAYOUT configured in profile and environment" bash -c "
  grep -q 'D2_LAYOUT=tala' /etc/profile.d/d2.sh && \
  grep -q 'D2_LAYOUT=tala' /etc/environment
"
check "compile diagram to SVG using default TALA layout" bash -c "
  tmp_svg=\"/tmp/d2_test.svg\"
  rm -f \"\$tmp_svg\"
  echo 'x -> y: default tala' | d2 - \"\$tmp_svg\"
  [ -s \"\$tmp_svg\" ] && grep -q '<svg' \"\$tmp_svg\"
"
check "compile diagram with explicit elk layout" bash -c "
  tmp_elk=\"/tmp/d2_elk.svg\"
  rm -f \"\$tmp_elk\"
  echo 'x -> y: elk layout' | d2 --layout elk - \"\$tmp_elk\"
  [ -s \"\$tmp_elk\" ] && grep -q '<svg' \"\$tmp_elk\"
"

reportResults
