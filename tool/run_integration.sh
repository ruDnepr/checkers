#!/usr/bin/env bash
set -o pipefail
flutter test integration_test/app_flow_test.dart --reporter expanded > /tmp/integration.txt 2>&1 || status=$?
cat /tmp/integration.txt
if [ -n "${status:-}" ]; then
  python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/integration.txt').read_text()
blocks = ['EXCEPTION CAUGHT' + b for b in text.split('EXCEPTION CAUGHT')[1:]] or [text[-3900:]]
for block in blocks[:8]:
    print('::error title=integration-output::' + block[:3900].replace('%','%25').replace('\n','%0A').replace('\r','%0D'))
PY
fi
exit "${status:-0}"
