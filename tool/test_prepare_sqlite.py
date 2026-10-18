import hashlib
from io import BytesIO
from pathlib import Path
import tempfile
import unittest
from prepare_sqlite import prepare


class Response(BytesIO):
    status = 200


class PrepareTest(unittest.TestCase):
    def test_retries_corrupt_download_and_repairs_corrupt_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'libsqlite3.so'
            path.write_bytes(b'bad cache')
            responses = iter([Response(b'proxy error'), Response(b'correct')])
            expected = hashlib.sha256(b'correct').hexdigest()
            prepare('https://example.com/lib', expected, path,
                    fetch=lambda *args, **kwargs: next(responses), pause=lambda _: None)
            self.assertEqual(path.read_bytes(), b'correct')
            prepare('https://example.com/lib', expected, path,
                    fetch=lambda *args, **kwargs: self.fail('Valid cache must be reused'))

    def test_never_installs_unverified_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'libsqlite3.so'
            with self.assertRaises(ValueError):
                prepare('https://example.com/lib', '0' * 64, path,
                        fetch=lambda *args, **kwargs: Response(b'bad'), pause=lambda _: None)
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix('.download').exists())

    def test_rejects_http_error_even_with_matching_body(self):
        with tempfile.TemporaryDirectory() as directory:
            def fetch(*args, **kwargs):
                response = Response(b'body')
                response.status = 503
                return response
            with self.assertRaisesRegex(ValueError, 'HTTP 503'):
                prepare('https://example.com/lib', hashlib.sha256(b'body').hexdigest(),
                        Path(directory) / 'libsqlite3.so', fetch=fetch, pause=lambda _: None)


if __name__ == '__main__':
    unittest.main()
