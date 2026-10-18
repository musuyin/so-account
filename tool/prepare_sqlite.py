"""Prime sqlite3's native-hook cache without weakening its integrity checks."""
import hashlib
import json
from pathlib import Path
import re
import sys
import time
from urllib.parse import urljoin, urlparse, unquote
from urllib.request import Request, urlopen


def prepare(url, expected, destination, fetch=None, pause=time.sleep):
    destination = Path(destination)
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix('.download')
    for attempt in range(4):
        try:
            request = Request(url, headers={'User-Agent': 'SoAccount-build', 'Cache-Control': 'no-cache'})
            with (fetch or urlopen)(request, timeout=90) as response:
                if response.status != 200:
                    raise ValueError(f'HTTP {response.status}')
                content = response.read()
            actual = hashlib.sha256(content).hexdigest()
            if actual != expected:
                raise ValueError(f'SHA-256 {actual}, expected {expected}')
            temporary.write_bytes(content)
            temporary.replace(destination)
            print(f'Verified {destination.name}: {expected}')
            return
        except Exception as error:
            temporary.unlink(missing_ok=True)
            print(f'Download attempt {attempt + 1}/4 failed: {error}', file=sys.stderr)
            if attempt == 3:
                raise
            pause(2 ** attempt)


def main(targets):
    root = Path(__file__).resolve().parent.parent
    config = root / '.dart_tool/package_config.json'
    package = next(p for p in json.loads(config.read_text())['packages'] if p['name'] == 'sqlite3')
    uri = urlparse(urljoin(config.as_uri(), package['rootUri']))
    package_path = Path(unquote(uri.path.lstrip('/') if sys.platform == 'win32' else uri.path))
    hashes = (package_path / 'lib/src/hook/asset_hashes.dart').read_text()
    tag = re.search(r"releaseTag = '(.*?)'", hashes).group(1)
    # This cache layout is an internal contract: review it when upgrading sqlite3.
    if tag != 'sqlite3-3.7.1':
        raise ValueError(f'Review native-hook cache layout for {tag}')
    assets = dict(re.findall(r"'(libsqlite3\.[^']+)': '([a-f0-9]{64})'", hashes))
    groups = {
        'android': ['libsqlite3.arm.android.so', 'libsqlite3.arm64.android.so', 'libsqlite3.x64.android.so'],
        'linux': ['libsqlite3.x64.linux.so'],
        'ios': ['libsqlite3.arm64.ios_sim.dylib', 'libsqlite3.x64.ios_sim.dylib',
                'libsqlite3.arm64.macos.dylib', 'libsqlite3.x64.macos.dylib'],
    }
    for target in targets:
        for name in groups[target]:
            expected = assets[name]
            filename = 'libsqlite3.dylib' if name.endswith('.dylib') else 'libsqlite3.so'
            destination = root / '.dart_tool/hooks_runner/shared/sqlite3/build' / f'download-{expected[:8]}' / filename
            prepare(f'https://github.com/simolus3/sqlite3.dart/releases/download/{tag}/{name}', expected, destination)


if __name__ == '__main__':
    main(sys.argv[1:])
