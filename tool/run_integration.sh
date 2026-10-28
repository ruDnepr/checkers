#!/usr/bin/env bash
# One app launch per test file: a crashing device test cannot take the rest of
# the suite with it, and each launch starts from a clean process.
set -o pipefail
status=0
: > /tmp/integration.txt
for file in integration_test/*_test.dart; do
  echo "=== $file" >> /tmp/integration.txt
  flutter test "$file" --reporter expanded >> /tmp/integration.txt 2>&1 || status=1
done
cat /tmp/integration.txt

# A device run can die without printing a Dart error. Collect the Android side
# so a failure is diagnosable from the check annotations.
{
  echo '--- adb devices'
  adb devices || true
  echo '--- crash buffer'
  adb logcat -b crash -d 2>/dev/null | tail -n 120 || true
  echo '--- last lines of the main log'
  adb logcat -d -v brief 2>/dev/null | tail -n 250 || true
  echo '--- app memory'
  adb shell dumpsys meminfo ru.dnepr.checkers_for_diana 2>/dev/null | head -n 20 || true
} > /tmp/device.txt 2>&1
cat /tmp/device.txt

if [ "$status" != 0 ]; then
  python3 - <<'PY'
from pathlib import Path

def emit(tag, text, keep=6):
    # Drop download/unzip progress noise and publish the tail in chunks so a
    # failure is visible in the check annotations.
    lines = [
        line
        for line in text.splitlines()
        if not line.startswith('[') and 'Unzipping' not in line
    ]
    clean = '\n'.join(lines)
    chunks = [clean[i:i + 3900] for i in range(0, len(clean), 3900)]
    for index, chunk in enumerate(chunks[-keep:]):
        print(
            f'::error title={tag}-{index:02d}::'
            + chunk.replace('%', '%25').replace('\n', '%0A').replace('\r', '%0D')
        )

emit('integration-output', Path('/tmp/integration.txt').read_text(errors='replace'))
emit('device-output', Path('/tmp/device.txt').read_text(errors='replace'))
PY
fi
exit "$status"
