"""Host-driven Android process-death test, confined to a synthetic debug package."""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import time

PACKAGE = 'dev.soaccount.so_account.recovery'
ACTIVITY = PACKAGE + '/dev.soaccount.so_account.MainActivity'
STAGES = ('seed', 'verify', 'restore-failure', 'verify-failure',
          'restore-crash', 'verify-failure', 'restore-success', 'verify')


def checked_package(badging):
    match = re.search(r"package: name='([^']+)'", badging)
    if not match or match[1] != PACKAGE:
        raise ValueError('Refusing an APK outside the dedicated recovery package')


class Driver:
    def __init__(self, adb, serial, output):
        self.command = [adb] + (['-s', serial] if serial else [])
        self.output = output

    def adb(self, *args, check=True):
        return subprocess.run([*self.command, *args], capture_output=True,
                              text=True, check=check, timeout=120).stdout.strip()

    def private_command(self, stage):
        if stage not in STAGES:
            raise ValueError('Unknown stage')
        command = (f'mkdir -p files; printf %s {shlex.quote(stage)} > files/recovery-command; '
                   'rm -f files/recovery-report.json')
        self.adb('shell', f'run-as {PACKAGE} sh -c {shlex.quote(command)}')

    def run_stage(self, stage):
        self.adb('shell', 'am', 'force-stop', PACKAGE)
        self.private_command(stage)
        self.adb('shell', 'am', 'start', '-W', '-n', ACTIVITY)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            raw = self.adb('shell', 'run-as', PACKAGE, 'cat',
                           'files/recovery-report.json', check=False)
            try:
                result = json.loads(raw)
            except (ValueError, TypeError):
                time.sleep(.5)
                continue
            if result.get('stage') == stage:
                self.adb('shell', 'am', 'force-stop', PACKAGE)
                expected = 'ready-to-kill' if stage == 'restore-crash' else 'passed'
                if result.get('status') != expected:
                    raise RuntimeError(json.dumps(result, ensure_ascii=False))
                return result
            time.sleep(.5)
        raise TimeoutError(f'No recovery report for {stage}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--serial')
    parser.add_argument('--output', default='.tooling/device-recovery')
    args = parser.parse_args()
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    badging = subprocess.run([args.aapt, 'dump', 'badging', args.apk],
                            capture_output=True, text=True, check=True).stdout
    checked_package(badging)
    driver = Driver(args.adb, args.serial, out)
    # No pm clear/uninstall: never erase an existing ledger, even a prior fixture.
    if driver.adb('shell', 'pm', 'path', PACKAGE, check=False):
        raise RuntimeError('Use a fresh emulator: recovery package already exists')
    evidence = {'package': PACKAGE, 'apk': badging.splitlines()[0],
                'device': driver.adb('shell', 'getprop'), 'stages': []}
    try:
        driver.adb('install', args.apk)
        for stage in STAGES:
            result = driver.run_stage(stage)
            evidence['stages'].append(result)
            (out / 'results.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
            print(f'{stage}: {result["status"]}', flush=True)
    finally:
        (out / 'logcat.txt').write_text(driver.adb('logcat', '-d', '-t', '3000'), encoding='utf-8')
        (out / 'results.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
