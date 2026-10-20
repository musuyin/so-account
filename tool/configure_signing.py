"""Create ONE persistent local release identity. Never prints signing secrets."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    directory = root / 'android' / 'signing'
    keystore = directory / 'so-account-release.jks'
    properties = root / 'android' / 'key.properties'
    if keystore.exists() or properties.exists():
        raise SystemExit('Signing files already exist; refusing to replace the update identity.')
    keytool = shutil.which('keytool')
    if not keytool and os.environ.get('JAVA_HOME'):
        candidate = Path(os.environ['JAVA_HOME']) / 'bin' / 'keytool.exe'
        if candidate.is_file():
            keytool = str(candidate)
    if not keytool:
        raise SystemExit('Set JAVA_HOME or put JDK keytool on PATH first.')
    directory.mkdir(parents=True, exist_ok=True)
    password = secrets.token_hex(32)
    env = dict(os.environ, SOACCOUNT_SIGNING_PASSWORD=password)
    subprocess.run([
        keytool, '-genkeypair', '-noprompt', '-keystore', str(keystore),
        '-storetype', 'PKCS12', '-alias', 'so-account', '-keyalg', 'RSA',
        '-keysize', '3072', '-validity', '36500', '-dname', 'CN=SoAccount',
        '-storepass:env', 'SOACCOUNT_SIGNING_PASSWORD',
        '-keypass:env', 'SOACCOUNT_SIGNING_PASSWORD',
    ], env=env, check=True, stdout=subprocess.DEVNULL)
    properties.write_text(
        f'storeFile={keystore.as_posix()}\nstorePassword={password}\n'
        f'keyAlias=so-account\nkeyPassword={password}\n', encoding='utf-8')
    if os.name != 'nt':
        keystore.chmod(0o600)
        properties.chmod(0o600)
    print('Created persistent signing files (gitignored). Back up both securely:')
    print(keystore)
    print(properties)


if __name__ == '__main__':
    main()
