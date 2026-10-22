import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from release_manifest import package
from release_deltas import generate


class ReleaseDeltaTests(unittest.TestCase):
    def test_publishes_only_byte_verified_smaller_patch_and_checks_baseline(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = b''.join(hashlib.sha256(str(i).encode()).digest() for i in range(4096))
            target = base[:65536] + b'new' + base[65539:]
            source = root / 'new.apk'
            source.write_bytes(target)
            output = root / 'release'
            package(source, 'version: 0.6.0+9\n', 'v0.6.0', output,
                    {'arm64-v8a': source})
            old_name = 'SoAccount-v0.5.3-android.apk'
            prefix = 'https://github.com/musuyin/so-account/releases/download/v0.5.3/'
            previous = {'package': 'dev.soaccount.so_account', 'build': 8, 'apk': old_name,
                        'size': len(base), 'sha256': hashlib.sha256(base).hexdigest()}
            release = {'tag_name': 'v0.5.3', 'draft': False, 'prerelease': False,
                       'assets': [{'name': n, 'browser_download_url': prefix + n}
                                  for n in [old_name, 'so-account-update.json']]}
            files = {prefix + old_name: base, prefix + 'so-account-update.json': json.dumps(previous).encode()}
            result = generate(output, [release], lambda url, maximum: files[url])
            self.assertEqual(len(result['patches']), 2)
            self.assertEqual({p['target'] for p in result['patches']},
                             {'SoAccount-v0.6.0-android.apk', 'SoAccount-v0.6.0-arm64-v8a.apk'})
            self.assertTrue(all(p['size'] < len(target) * .8 for p in result['patches']))
            files[prefix + old_name] = b'corrupt'
            with self.assertRaises(ValueError):
                generate(output, [release], lambda url, maximum: files[url])


if __name__ == '__main__':
    unittest.main()
