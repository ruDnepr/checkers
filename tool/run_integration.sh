#!/usr/bin/env bash
set -o pipefail
flutter test integration_test/app_flow_test.dart --reporter expanded > /tmp/integration.txt 2>&1 || status=$?
cat /tmp/integration.txt

# A device run can die without printing a Dart error (the emulator goes
# offline). Collect the Android side so a failure is diagnosable.
{
  echo '--- adb devices'
  adb devices || true
  echo '--- logcat: crashes, kills and memory pressure'
  adb logcat -d 2>/dev/null \
    | grep -Ei 'FATAL|AndroidRuntime|lowmemorykiller|OutOfMemory|ANR in|Killing|flutter' \
    | tail -n 120 || true
  echo '--- app memory'
  adb shell dumpsys meminfo ru.dnepr.checkers_for_diana 2>/dev/null | head -n 20 || true
} > /tmp/device.txt 2>&1
cat /tmp/device.txt

if [ -n "${status:-}" ]; then
  python3 - <<'PY'
from pathlib import Path

def emit(tag, text):
    # Drop download/unzip progress noise and publish the tail in chunks so a
    # failure is visible in the check annotations.
    lines = [
        line
        for line in text.splitlines()
        if not line.startswith('[') and 'Unzipping' not in line
    ]
    clean = '\n'.join(lines)
    chunks = [clean[i:i + 3900] for i in range(0, len(clean), 3900)]
    for index, chunk in enumerate(chunks[-6:]):
        print(
            f'::error title={tag}-{index:02d}::'
            + chunk.replace('%', '%25').replace('\n', '%0A').replace('\r', '%0D')
        )

emit('integration-output', Path('/tmp/integration.txt').read_text(errors='replace'))
emit('device-output', Path('/tmp/device.txt').read_text(errors='replace'))
PY
fi
exit "${status:-0}"
