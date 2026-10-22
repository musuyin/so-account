import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock

from release_manifest import package
from release_deltas import generate, load_releases, fetch


class ReleaseDeltaTests(unittest.TestCase):
    def test_public_api_requests_versioned_json_without_authentication(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'[]'
        with patch('urllib.request.urlopen', return_value=response) as request:
            self.assertEqual(fetch('https://api.github.com/repos/musuyin/so-account/releases?per_page=10', 1024), b'[]')
        headers = dict((key.lower(), value) for key, value in request.call_args.args[0].header_items())
        self.assertEqual(headers['accept'], 'application/vnd.github+json')
        self.assertEqual(headers['x-github-api-version'], '2022-11-28')
        self.assertEqual(headers['cache-control'], 'no-cache')
        self.assertNotIn('authorization', headers)

    def test_baseline_discovery_uses_public_collection_without_credentials(self):
        calls = []
        def public_download(url, maximum):
            calls.append(url)
            return b'[{"tag_name":"v0.5.3"}]'
        self.assertEqual(load_releases(public_download), [{'tag_name': 'v0.5.3'}])
        self.assertEqual(calls, ['https://api.github.com/repos/musuyin/so-account/releases?per_page=10'])
        with self.assertRaises(ValueError):
            load_releases(lambda url, maximum: b'{}')

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
