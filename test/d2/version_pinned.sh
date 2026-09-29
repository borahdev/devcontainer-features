#!/bin/bash
set -e

source dev-container-features-test-lib

check "d2 binary on PATH" bash -c "command -v d2"
check "d2 version is 0.9.0" bash -c "d2 version | grep -q '0.9.0'"
check "d2 layout contains tala" bash -c "d2 layout | grep -qi 'tala'"
check "compile diagram on pinned release" bash -c "
  tmp_svg=\"/tmp/d2_pinned_test.svg\"
  rm -f \"\$tmp_svg\"
  echo 'stage1 -> stage2: pipeline' | d2 - \"\$tmp_svg\"
  [ -s \"\$tmp_svg\" ] && grep -q '<svg' \"\$tmp_svg\"
"

reportResults

