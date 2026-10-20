"""Package a universal APK and its versioned in-app update manifest."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


def package(apk, pubspec, tag, output):
    match = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$', pubspec, re.MULTILINE)
    if not match or tag != f'v{match[1]}' or int(match[2]) <= 0:
        raise ValueError('Release tag must match pubspec version and positive build number')
    apk = Path(apk)
    size = apk.stat().st_size
    if not 0 < size <= 250 * 1024 * 1024:
        raise ValueError('APK size outside supported range')
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    name = f'SoAccount-{tag}-android.apk'
    with apk.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    shutil.copyfile(apk, output / name)
    manifest = {
        'schema': 1, 'package': 'dev.soaccount.so_account',
        'version': match[1], 'build': int(match[2]),
        'apk': name, 'size': size, 'sha256': digest,
    }
    (output / 'so-account-update.json').write_text(
        json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (output / 'SHA256SUMS.txt').write_text(f'{digest}  {name}\n', encoding='utf-8')
    return manifest


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python tool/release_manifest.py vX.Y.Z')
    package('build/app/outputs/flutter-apk/app-release.apk',
            Path('pubspec.yaml').read_text(encoding='utf-8'), sys.argv[1], '.tooling/release')
