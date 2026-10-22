"""Generate verified deltas from the two latest public releases, never mutable builds."""
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.request

from delta_patch import apply_patch, create_patch, MAX_APK

REPO = 'musuyin/so-account'


def fetch(url, maximum, *, api=False):
    headers = {'User-Agent': 'SoAccount-release'}
    if api and os.environ.get('GH_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=45) as response:
                content = response.read(maximum + 1)
                if len(content) > maximum:
                    raise ValueError('Release download exceeds limit')
                return content
        except (OSError, TimeoutError):
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))


def asset(release, name):
    files = [a for a in release['assets'] if a['name'] == name]
    if len(files) != 1:
        raise ValueError('Missing or ambiguous baseline asset')
    item = files[0]
    prefix = f'https://github.com/{REPO}/releases/download/{release["tag_name"]}/'
    if item['browser_download_url'] != prefix + name:
        raise ValueError('Unexpected baseline source')
    return item


def generate(output, releases, download=fetch):
    output = Path(output)
    manifest_path = output / 'so-account-update.json'
    manifest = json.loads(manifest_path.read_text())
    cache = output.parent / 'delta-baselines'
    cache.mkdir(parents=True, exist_ok=True)
    targets = [{'abi': 'universal', **{k: manifest[k] for k in ['apk', 'size', 'sha256']}}] + manifest.get('variants', [])
    patches = []
    candidates = [r for r in releases if not r['draft'] and not r['prerelease'] and
                  re.fullmatch(r'v\d+\.\d+\.\d+', r['tag_name']) and r['tag_name'] != 'v' + manifest['version']][:2]
    for release in candidates:
        info = asset(release, 'so-account-update.json')
        previous = json.loads(download(info['browser_download_url'], 1024 * 1024))
        if previous['package'] != manifest['package'] or previous['build'] >= manifest['build']:
            continue
        bases = [{'abi': 'universal', **{k: previous[k] for k in ['apk', 'size', 'sha256']}}] + previous.get('variants', [])
        for base in bases:
            abi = base['abi']
            expected_name = f'SoAccount-{release["tag_name"]}-' + ('android' if abi == 'universal' else abi) + '.apk'
            if base['apk'] != expected_name or not re.fullmatch('[a-f0-9]{64}', base['sha256']):
                raise ValueError('Invalid baseline metadata')
            compatible = [t for t in targets if abi == 'universal' or t['abi'] == abi]
            if not compatible:
                continue
            remote = asset(release, base['apk'])
            content = download(remote['browser_download_url'], MAX_APK)
            if len(content) != base['size'] or hashlib.sha256(content).hexdigest() != base['sha256']:
                raise ValueError('Baseline digest/size mismatch')
            base_file = cache / (base['sha256'] + '.apk')
            base_file.write_bytes(content)
            for target in compatible:
                name = f'SoAccount-v{manifest["version"]}-from-{release["tag_name"]}-{target["abi"]}-{base["sha256"][:12]}.sodelta'
                patch = output / name
                create_patch(base_file, output / target['apk'], patch)
                if patch.stat().st_size >= target['size'] * 0.8:
                    patch.unlink()
                    print(f'No useful delta for {target["abi"]} from {release["tag_name"]}', flush=True)
                    continue
                reconstructed = cache / 'verified.apk'
                apply_patch(base_file, patch, reconstructed)
                if hashlib.sha256(reconstructed.read_bytes()).hexdigest() != target['sha256']:
                    raise ValueError('Reconstructed APK differs from signed release')
                reconstructed.unlink()
                patches.append({'algorithm': 'soaccount-copy-v1', 'target': target['apk'],
                    'targetSha256': target['sha256'], 'file': name, 'size': patch.stat().st_size,
                    'sha256': hashlib.sha256(patch.read_bytes()).hexdigest(),
                    'baseSha256': base['sha256'], 'baseSize': base['size']})
                print(f'Verified delta {name}: {patch.stat().st_size}/{target["size"]} bytes', flush=True)
    manifest['patches'] = patches
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (output / 'SHA256SUMS.txt').write_text(''.join(
        f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n'
        for p in sorted(output.iterdir()) if p.suffix in ['.apk', '.sodelta']), encoding='utf-8')
    return manifest


if __name__ == '__main__':
    releases = json.loads(fetch(f'https://api.github.com/repos/{REPO}/releases?per_page=10', 4 * 1024 * 1024, api=True))
    generate('.tooling/release', releases)
