import gzip
import hashlib
import io
from pathlib import Path
import struct
import tempfile
import unittest
from zipfile import ZipFile, ZIP_STORED

from delta_patch import create_patch, apply_patch, HEADER, MAGIC


class DeltaTests(unittest.TestCase):
    def test_zip_members_survive_moved_offsets_and_preserve_signed_trailer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shared = b''.join(hashlib.sha256(str(i).encode()).digest() for i in range(8192))
            for name, prefix in [('base', b'old'), ('target', b'new content changing offsets')]:
                with ZipFile(root / name, 'w', compression=ZIP_STORED) as archive:
                    archive.writestr('first', prefix)
                    archive.writestr('lib/arm64-v8a/libflutter.so', shared)
                    archive.writestr('signature', name.encode())
            create_patch(root / 'base', root / 'target', root / 'patch')
            apply_patch(root / 'base', root / 'patch', root / 'out')
            self.assertEqual((root / 'out').read_bytes(), (root / 'target').read_bytes())
            self.assertLess((root / 'patch').stat().st_size, 2000)
            (root / 'base').write_bytes(b'wrong base')
            with self.assertRaises(ValueError):
                apply_patch(root / 'base', root / 'patch', root / 'out')

    def test_rejects_bad_bounds_truncation_and_output_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = b'x' * 256
            (root / 'base').write_bytes(base)
            header = HEADER.pack(MAGIC, len(base), len(base), hashlib.sha256(base).digest(), hashlib.sha256(base).digest())
            for body in [b'\x00' + struct.pack('<QI', 255, 10) + b'\xff',
                         b'\x01' + struct.pack('<I', 1024 * 1024 + 1),
                         b'\x02', b'\xff', b'\x01\x00',
                         b'\x01' + struct.pack('<I', 256) + b'y' * 256 + b'\xff']:
                (root / 'patch').write_bytes(header + gzip.compress(body))
                with self.assertRaises((ValueError, EOFError)):
                    apply_patch(root / 'base', root / 'patch', root / 'out')


if __name__ == '__main__':
    unittest.main()
