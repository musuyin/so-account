"""Build with bounded retries for dependency resolution failures, keeping logs."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def dependency_failure(output):
    # Compiler/test errors must fail immediately, even if other lines mention downloads.
    if re.search(r'(Compilation failed|Compilation error|Error:|error:|Execution failed for task)', output):
        return False
    return bool(re.search(
        r'(could not resolve plugin artifact|Could not resolve all (?:files|artifacts|dependencies)|'
        r'Could not (?:GET|HEAD)|Read timed out|Connection timed out|'
        r'Remote host terminated the handshake|Received status code (?:429|5\d\d))',
        output,
    ))


def build(command, log_dir, run=None, pause=time.sleep):
    log_dir = Path(log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, 4):
        log = log_dir / f'android-build-{attempt}.log'
        print(f'Android build attempt {attempt}/3; log: {log}', flush=True)
        with log.open('w', encoding='utf-8') as output:
            result = (run or subprocess.run)(command, stdout=output, stderr=subprocess.STDOUT,
                                             text=True, check=False)
        content = log.read_text(encoding='utf-8', errors='replace')
        # Full verbose logs stay in the artifact; keep the job output readable.
        print('\n'.join(content.splitlines()[-100:]), flush=True)
        if result.returncode == 0:
            return 0
        if attempt == 3 or not dependency_failure(content):
            return result.returncode
        print('Dependency resolution failed; retrying without deleting caches.', flush=True)
        pause(10 * attempt)
    return 1


if __name__ == '__main__':
    flutter = shutil.which('flutter')
    if flutter is None:
        raise SystemExit('flutter must be on PATH')
    raise SystemExit(build([flutter, 'build', 'apk', '--debug', '--verbose'],
                          '.tooling/ci-logs'))
