#!/usr/bin/env bash
set -o pipefail
flutter test integration_test/app_flow_test.dart --reporter expanded > /tmp/integration.txt 2>&1 || status=$?
cat /tmp/integration.txt
if [ -n "${status:-}" ]; then
  python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/integration.txt').read_text(errors='replace')
# Drop download/unzip progress noise, keep the readable run log, and publish the
# tail in chunks so a failure is visible in the check annotations.
lines = [
    line
    for line in text.splitlines()
    if not line.startswith('[') and 'Unzipping' not in line
]
clean = '\n'.join(lines)
chunks = [clean[i:i + 3900] for i in range(0, len(clean), 3900)]
for index, chunk in enumerate(chunks[-10:]):
    print(
        f'::error title=integration-output-{index:02d}::'
        + chunk.replace('%', '%25').replace('\n', '%0A').replace('\r', '%0D')
    )
PY
fi
exit "${status:-0}"
