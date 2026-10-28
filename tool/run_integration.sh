#!/usr/bin/env bash
# One app launch per test file: a crashing device test cannot take the rest of
# the suite with it, and each launch starts from a clean process.
set -o pipefail
status=0
: > /tmp/integration.txt
if ! timeout 180 adb wait-for-device; then
  echo 'Эмулятор не подключился к adb' >> /tmp/integration.txt
  status=1
elif [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; then
  echo 'Эмулятор не закончил загрузку' >> /tmp/integration.txt
  status=1
else
  # The first Gradle build of a cold runner downloads plugins and CMake and can
  # take minutes; warm it once here so the per-test runs stay fast and a slow
  # download is never mistaken for a hung test.
  echo '=== прогрев сборки' >> /tmp/integration.txt
  if ! timeout --signal=KILL 900 flutter build apk --debug \
    >> /tmp/integration.txt 2>&1; then
    echo 'Сборка debug APK не удалась' >> /tmp/integration.txt
    status=1
  fi
  for file in integration_test/*_test.dart; do
    echo "=== $file" >> /tmp/integration.txt
    # A wedged emulator can leave `flutter test` waiting forever, so every run
    # is bounded and a failure still leaves the log for the annotations.
    timeout --signal=KILL 420 flutter test "$file" --reporter expanded \
      >> /tmp/integration.txt 2>&1 || status=1
  done
fi
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

text = Path('/tmp/integration.txt').read_text(errors='replace')

# A one-line verdict per file, so the failing scenario is visible at a glance.
rows = []
current = None
passed = False
for line in text.splitlines():
    if line.startswith('=== integration_test/'):
        if current:
            rows.append(f'{current}: ' + ('ok' if passed else 'СБОЙ'))
        current = line[len('=== '):]
        passed = False
    elif 'All tests passed!' in line:
        passed = True
if current:
    rows.append(f'{current}: ' + ('ok' if passed else 'СБОЙ'))
print(
    '::error title=integration-summary::'
    + '%0A'.join(rows).replace('%', '%25')
)

emit('integration-output', text)
emit('device-output', Path('/tmp/device.txt').read_text(errors='replace'))
PY
fi
exit "$status"
