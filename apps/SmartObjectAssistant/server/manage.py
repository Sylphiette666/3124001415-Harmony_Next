"""Local-only provisioning. Secrets are written to ignored .local files."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import secrets
import shutil
from .app import LOCAL, ROOT, connect, key_digest


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('init')
    provision = commands.add_parser('provision')
    provision.add_argument('--device-id', required=True)
    publish = commands.add_parser('publish')
    publish.add_argument('--version', required=True)
    publish.add_argument('--file', type=Path, default=ROOT / 'entry/src/main/resources/rawfile/yolov13n.onnx')
    args = parser.parse_args()
    LOCAL.mkdir(exist_ok=True)
    if args.command == 'init':
        key = LOCAL / 'jwt-secret.txt'
        if not key.exists():
            key.write_text(secrets.token_urlsafe(48), encoding='utf-8')
        with connect(LOCAL / 'records.db'):
            pass
        print('Server initialized. Private state: .local (not committed).')
    elif args.command == 'provision':
        if not re.fullmatch(r'[A-Za-z0-9_-]{3,100}', args.device_id):
            parser.error('device-id must contain 3-100 letters, digits, underscores or hyphens')
        key = secrets.token_urlsafe(32)
        with connect(LOCAL / 'records.db') as db:
            db.execute('INSERT OR REPLACE INTO devices VALUES (?,?)', (args.device_id, key_digest(key)))
        path = LOCAL / f'{args.device_id}-device-key.txt'
        path.write_text(key, encoding='utf-8')
        print(f'Device provisioned. Enter the private key from {path} in App settings.')
    elif args.command == 'publish':
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,39}', args.version):
            parser.error('invalid version')
        source = args.file.resolve()
        if not source.is_file() or not 1000 < source.stat().st_size <= 64000000:
            parser.error('expected an ONNX model between 1 KB and 64 MB')
        models = LOCAL / 'models'
        models.mkdir(exist_ok=True)
        target = models / f'yolov13n-{args.version}.onnx'
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            parser.error('version already exists with different model bytes; publish a new version')
        temporary = target.with_suffix('.part')
        shutil.copyfile(source, temporary)
        temporary.replace(target)
        manifest = {'version': args.version, 'path': str(target.resolve()),
                    'sha256': digest, 'size': target.stat().st_size}
        pending = LOCAL / 'model.pending.json'
        pending.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        pending.replace(LOCAL / 'model.json')
        print(f'Published model {args.version}, SHA256 {manifest["sha256"]}.')


if __name__ == '__main__':
    main()
