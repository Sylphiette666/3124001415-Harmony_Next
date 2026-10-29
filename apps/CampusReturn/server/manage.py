"""Provision local accounts without shipping passwords or trusting client roles."""
import argparse
import base64
import json
import secrets
import time
from pathlib import Path

from .app import LOCAL, ROOT, create_app
from .database import connect
from .engine import credential_hash
from .service import Service


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['init', 'demo'])
    parser.add_argument('--seed', action='store_true')
    args = parser.parse_args()
    create_app()
    key = (LOCAL / 'jwt-secret.txt').read_text(encoding='utf-8').strip()
    if args.command == 'demo':
        credentials_path = LOCAL / 'accounts.json'
        accounts = json.loads(credentials_path.read_text(encoding='utf-8')) if credentials_path.exists() else []
        with connect(LOCAL / 'campus.db') as db:
            for id, name, role in [('alice','失主A','user'),('bob','拾获者B','user'),('charlie','认领者C','user'),('admin','平台管理员','admin')]:
                if not db.execute('SELECT 1 FROM users WHERE id=?', (id,)).fetchone():
                    secret = secrets.token_urlsafe(32)
                    db.execute('INSERT INTO users(id,name,role,secret) VALUES (?,?,?,?)', (id, name, role, credential_hash(secret, key)))
                    accounts.append({'id': id, 'name': name, 'role': role, 'deviceKey': secret})
            if args.seed:
                s = Service(db, key); now = int(time.time() * 1000)
                picture = base64.b64encode((ROOT / 'entry/src/main/resources/rawfile/demo-card.jpg').read_bytes()).decode()
                for id, owner, kind in [('demo-lost-alice','alice','lost'),('demo-lost-charlie','charlie','lost'),('demo-found-bob','bob','found')]:
                    if db.execute('SELECT 1 FROM items WHERE id=?', (id,)).fetchone(): continue
                    s.publish(s.user(owner), {'itemId':id,'kind':kind,'category':'校园卡','color':'蓝色','place':'图书馆',
                              'occurredAt':now - (7200000 if kind=='lost' else 3600000), 'description':'蓝色校园卡，图书馆门口，姓名张同学，编号202600001，仅演示',
                              'ocrText':'校园卡 张同学 202600001 仅演示','imageBase64':picture,
                              'question':'卡上演示编号是什么？' if kind=='found' else '', 'answer':'202600001' if kind=='found' else ''})
                book_picture = base64.b64encode((ROOT / 'entry/src/main/resources/rawfile/demo-book.jpg').read_bytes()).decode()
                for id, owner, kind, place, clue in [
                    ('demo-book-lost','alice','lost','图书馆','BK20260001'),
                    ('demo-book-near','bob','found','图书馆','BK00009999'),
                    ('demo-book-text','bob','found','操场','BK20260001')]:
                    if db.execute('SELECT 1 FROM items WHERE id=?', (id,)).fetchone(): continue
                    s.publish(s.user(owner), {'itemId':id,'kind':kind,'category':'书籍','color':'蓝色','place':place,
                              'occurredAt':now - (7200000 if kind=='lost' else 3600000),
                              'description':('算法导论 第三版 蓝色 扉页编号 ' + clue) if clue == 'BK20260001' else '蓝色书本 编号 ' + clue,
                              'ocrText':clue, 'imageBase64':book_picture if clue == 'BK20260001' else base64.b64encode((ROOT / 'entry/src/main/resources/rawfile/demo-book-near.jpg').read_bytes()).decode(),
                              'question':'扉页编号是什么？' if kind=='found' else '', 'answer':clue if kind=='found' else ''})
        credentials_path.write_text(json.dumps(accounts, ensure_ascii=False, indent=2), encoding='utf-8')
        print('Accounts provisioned. Private credentials: .local/accounts.json (not committed).')
    else:
        print('Local server initialized. Run: python -m server.manage demo --seed')


if __name__ == '__main__': main()
