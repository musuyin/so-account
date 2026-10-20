import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from release_manifest import package


class ReleaseManifestTests(unittest.TestCase):
    def test_packs_apk_with_matching_digest_and_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apk = root / 'app-release.apk'
            apk.write_bytes(b'synthetic APK')
            manifest = package(apk, 'version: 0.5.0+5\n', 'v0.5.0', root / 'out')
            self.assertEqual(manifest['build'], 5)
            self.assertEqual(manifest['sha256'], hashlib.sha256(apk.read_bytes()).hexdigest())
            self.assertEqual(json.loads((root / 'out/so-account-update.json').read_text()), manifest)
            self.assertEqual((root / 'out/SoAccount-v0.5.0-android.apk').read_bytes(), apk.read_bytes())

    def test_rejects_wrong_tag_and_version(self):
        for version, tag in [('0.5.0+5', 'v0.6.0'), ('0.5.0+0', 'v0.5.0'), ('0.5.0-beta+5', 'v0.5.0')]:
            with self.assertRaises(ValueError):
                package('unused.apk', f'version: {version}\n', tag, 'unused')


if __name__ == '__main__':
    unittest.main()
