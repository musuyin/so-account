"""Restore signing from CI secrets; never fall back to a debug identity."""
import base64
import os
from pathlib import Path


def restore():
    names = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD',
             'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')
    if not all(os.environ.get(name) for name in names):
        raise SystemExit('Missing persistent Android signing secrets. See docs/engineering/app-updates.md')
    root = Path(__file__).resolve().parent.parent
    store = root / '.tooling/signing/so-account-release.jks'
    store.parent.mkdir(parents=True, exist_ok=True)
    store.write_bytes(base64.b64decode(os.environ[names[0]], validate=True))
    store.chmod(0o600)
    properties = root / 'android/key.properties'
    values = {
        'storeFile': store.as_posix(),
        'storePassword': os.environ[names[1]],
        'keyAlias': os.environ[names[2]],
        'keyPassword': os.environ[names[3]],
    }
    def escape(value):
        return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace(' ', '\\ ')
    properties.write_text(''.join(f'{key}={escape(value)}\n' for key, value in values.items()), encoding='utf-8')
    properties.chmod(0o600)
    print('Persistent signing restored; credentials were not logged.')


if __name__ == '__main__':
    restore()
