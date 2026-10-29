from contextlib import contextmanager
import json
import secrets
import time
from pathlib import Path

from fastapi import FastAPI, Depends, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import jwt
from pydantic import BaseModel, ConfigDict, Field, model_validator
from typing import Literal

from .database import connect, encode
from .engine import CATEGORIES, DEFAULT, DomainError, image_bytes, require, credential_hash, validate_policy
from .service import Service

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / '.local'


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)


class Auth(Strict):
    deviceId: str = Field(min_length=3, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    deviceKey: str = Field(min_length=16, max_length=200)


class Item(Strict):
    itemId: str = Field(min_length=8, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    kind: Literal['lost', 'found']
    category: str = Field(max_length=30)
    color: str = Field(default='', max_length=30)
    place: str = Field(min_length=1, max_length=100)
    occurredAt: int = Field(ge=946684800000, le=32503680000000)
    description: str = Field(min_length=2, max_length=2000)
    ocrText: str = Field(default='', max_length=4000)
    imageBase64: str = Field(min_length=10, max_length=2100000)
    question: str = Field(default='', max_length=200)
    answer: str = Field(default='', max_length=200)

    @model_validator(mode='after')
    def check(self):
        require(self.category in CATEGORIES, 'INVALID_CATEGORY', '请选择支持的物品类别', 422)
        require(self.kind != 'found' or bool(self.question and self.answer), 'PROOF_QUESTION_REQUIRED', '招领启事须设置凭证问题和答案', 422)
        image_bytes(self.imageBase64)
        return self


class Pair(Strict):
    lostId: str
    foundId: str


class Answer(Strict):
    answer: str = Field(min_length=1, max_length=200)
    level: int = Field(default=1, ge=1, le=3)
    evidenceText: str = Field(default='', max_length=4000)
    evidenceImage: str = Field(default='', max_length=2100000)


class Review(Strict):
    passed: bool
    score: int = Field(ge=0, le=100)


class Appeal(Strict):
    lostId: str
    level: int = Field(ge=1, le=3)
    evidenceText: str = Field(min_length=2, max_length=4000)
    evidenceImage: str = Field(default='', max_length=2100000)


class Decision(Strict):
    valid: bool


class Policy(Strict):
    weights: dict[str, float]
    threshold: float
    windowHours: int
    matchHours: int
    appealHours: int
    creditFloor: int
    banCount: int
    credit: dict[str, int]


class Violation(Strict):
    userId: str
    kind: Literal['false_post', 'no_show']
    reasonId: str = Field(min_length=8, max_length=100)


def create_app(database=None, key=None, clock=None):
    if database is None:
        LOCAL.mkdir(exist_ok=True)
        database = LOCAL / 'campus.db'
    database = Path(database)
    database.parent.mkdir(parents=True, exist_ok=True)
    if key is None:
        path = LOCAL / 'jwt-secret.txt'
        if not path.exists(): path.write_text(secrets.token_urlsafe(48), encoding='utf-8')
        key = path.read_text(encoding='utf-8').strip()
    with connect(database): pass
    app = FastAPI(title='归物校园失物招领', version='1.0.0')
    bearer = HTTPBearer(auto_error=False)

    @app.middleware('http')
    async def body_limit(request: Request, call_next):
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 16000000:
                return JSONResponse({'error': {'code': 'BODY_TOO_LARGE', 'message': '请求过大，请缩小图片后重试'}}, status_code=413)
        request._body = bytes(body)
        return await call_next(request)

    @app.exception_handler(DomainError)
    async def domain_error(request, error):
        return JSONResponse({'error': {'code': error.code, 'message': error.message}}, status_code=error.status)

    @app.exception_handler(RequestValidationError)
    async def invalid(request, error):
        return JSONResponse({'error': {'code': 'VALIDATION_ERROR', 'message': '参数格式不正确，请检查必填字段和数值范围'}}, status_code=422)

    def identity(auth: HTTPAuthorizationCredentials | None = Depends(bearer)):
        require(auth is not None, 'AUTH_REQUIRED', '请先配置账号并连接服务', 401)
        try:
            data = jwt.decode(auth.credentials, key, algorithms=['HS256'], audience='campus-return', issuer='campus-return', options={'require': ['exp', 'iat', 'sub', 'role']})
            with connect(database) as db:
                u = Service(db, key, clock).user(data['sub'])
            require(data['role'] == u['role'], 'AUTH_REQUIRED', '角色已变化，请重新登录', 401)
            return u
        except jwt.PyJWTError:
            raise DomainError('AUTH_REQUIRED', '登录已过期，请重新连接', 401)

    def admin(user=Depends(identity)):
        require(user['role'] == 'admin', 'FORBIDDEN', '需要平台管理员权限', 403)
        return user

    @contextmanager
    def service():
        with connect(database) as db:
            s = Service(db, key, clock); s.expire(); yield s

    @app.get('/health')
    def health(): return {'status': 'ok', 'service': 'campus-return'}

    @app.post('/v1/auth/token')
    def login(body: Auth):
        with connect(database) as db:
            row = db.execute('SELECT * FROM users WHERE id=?', (body.deviceId,)).fetchone()
            require(row is not None and secrets.compare_digest(row['secret'], credential_hash(body.deviceKey, key)), 'AUTH_REQUIRED', '账号或设备密钥不正确', 401)
            now = int(time.time())
            token = jwt.encode({'sub': row['id'], 'role': row['role'], 'iat': now, 'exp': now + 300, 'aud': 'campus-return', 'iss': 'campus-return'}, key, algorithm='HS256')
            return {'accessToken': token, 'expiresIn': 300, 'tokenType': 'Bearer'}

    @app.get('/v1/me')
    def me(user=Depends(identity)):
        with service() as s: return s.profile(user['id'])

    @app.post('/v1/items')
    def publish(body: Item, user=Depends(identity)):
        with service() as s: return s.publish(s.user(user['id']), body.model_dump())

    @app.get('/v1/sync')
    def sync(cursor: int = 0, limit: int = 50, user=Depends(identity)):
        require(cursor >= 0 and 1 <= limit <= 100, 'INVALID_PAGE', '增量同步参数无效', 422)
        with service() as s:
            rows = list(s.db.execute('SELECT * FROM changes WHERE seq>? ORDER BY seq LIMIT ?', (cursor, limit)))
            ids = list(dict.fromkeys(r['item_id'] for r in rows))
            return {'items': [s.public_item(id, user) for id in ids], 'cursor': rows[-1]['seq'] if rows else cursor, 'hasMore': len(rows) == limit}

    @app.get('/v1/items')
    def items(kind: str = '', category: str = '', mine: bool = False, page: int = 1, pageSize: int = 20, user=Depends(identity)):
        require(page >= 1 and 1 <= pageSize <= 100, 'INVALID_PAGE', '分页参数无效', 422)
        with service() as s:
            ids = [r['id'] for r in s.db.execute("SELECT id FROM items WHERE (?='' OR kind=?) AND (?='' OR json_extract(data,'$.category')=?) AND (?='' OR owner=?) ORDER BY json_extract(data,'$.occurredAt') DESC,id", (kind, kind, category, category, user['id'] if mine else '', user['id']))]
            return {'items': [s.public_item(id, user) for id in ids[(page-1)*pageSize:page*pageSize]], 'total': len(ids)}

    @app.get('/v1/candidates/{lost_id}')
    def candidates(lost_id: str, user=Depends(identity)):
        with service() as s: return {'candidates': s.candidates(user, lost_id), 'policy': s.policy}

    @app.post('/v1/matches')
    def match_pair(body: Pair, user=Depends(identity)):
        with service() as s:
            lost, found = s.item(body.lostId), s.item(body.foundId)
            require(lost['owner'] == user['id'] or found['owner'] == user['id'] or user['role'] == 'admin', 'FORBIDDEN', '只能操作自己的物品', 403)
            result = s.create_match(lost, found, user['id']); return {'matchId': result['id'], 'state': result['state']}

    @app.post('/v1/claims')
    def claim(body: Pair, user=Depends(identity)):
        with service() as s: return s.claim(s.user(user['id']), body.lostId, body.foundId)

    @app.post('/v1/claims/{id}/answer')
    def answer(id: str, body: Answer, user=Depends(identity)):
        with service() as s: return s.answer(user, id, body.model_dump())

    @app.post('/v1/claims/{id}/review')
    def review(id: str, body: Review, user=Depends(identity)):
        with service() as s: return s.review(user, id, body.model_dump())

    @app.get('/v1/matches')
    def matches(user=Depends(identity)):
        with service() as s:
            result = []
            for m in s.db.execute('SELECT * FROM matches ORDER BY created DESC,id'):
                if user['role'] == 'admin' or user['id'] in [s.item(m['lost'])['owner'], s.item(m['found'])['owner']]: result.append(s.view_match(dict(m), user))
            return {'matches': result}

    @app.get('/v1/matches/{id}')
    def one_match(id: str, user=Depends(identity)):
        with service() as s:
            m = s.match(id)
            require(user['role'] == 'admin' or user['id'] in [s.item(m['lost'])['owner'], s.item(m['found'])['owner']] or m['state'] in ['已完成','申诉中'], 'FORBIDDEN', '不能查看他人的未完成流程', 403)
            return s.view_match(m, user)

    @app.post('/v1/matches/{id}/complete')
    def complete(id: str, user=Depends(identity)):
        with service() as s: return s.complete(s.user(user['id']), id)

    @app.post('/v1/matches/{id}/appeals')
    def appeal(id: str, body: Appeal, user=Depends(identity)):
        with service() as s: return s.appeal(user, id, body.model_dump())

    @app.get('/v1/appeals')
    def appeals(user=Depends(identity)):
        with service() as s:
            rows = [dict(a) for a in s.db.execute('SELECT * FROM appeals ORDER BY created DESC') if user['role'] == 'admin' or a['user_id'] == user['id'] or s.item(s.match(a['match_id'])['found'])['owner'] == user['id']]
            return {'appeals': [{'appealId': a['id'], 'matchId': a['match_id'], 'userId': a['user_id'], 'level': a['level'], 'evidenceText': a['evidence'], 'evidenceImage': a['image'], 'state': a['state'], 'decision': a['decision'], 'deadline': a['deadline']} for a in rows]}

    @app.post('/v1/appeals/{id}/decision')
    def decide(id: str, body: Decision, user=Depends(identity)):
        with service() as s: return s.decide(user, id, body.valid)

    @app.get('/v1/notifications')
    def notifications(user=Depends(identity)):
        with service() as s: return {'notifications': [dict(r) for r in s.db.execute('SELECT * FROM notifications WHERE user_id=? ORDER BY id DESC LIMIT 100', (user['id'],))]}

    @app.get('/v1/admin')
    def dashboard(user=Depends(admin)):
        with service() as s:
            stats = {'users': s.db.execute('SELECT COUNT(*) FROM users').fetchone()[0], 'items': s.db.execute('SELECT COUNT(*) FROM items').fetchone()[0],
                     'matches': s.db.execute('SELECT COUNT(*) FROM matches').fetchone()[0], 'pendingAppeals': s.db.execute("SELECT COUNT(*) FROM appeals WHERE state='待裁定'").fetchone()[0],
                     'completed': s.db.execute("SELECT COUNT(*) FROM matches WHERE state='已完成'").fetchone()[0]}
            categories = [dict(r) for r in s.db.execute("SELECT json_extract(data,'$.category') name,COUNT(*) count FROM items GROUP BY name ORDER BY count DESC,name")]
            users = [s.profile(r['id']) for r in s.db.execute('SELECT * FROM users WHERE credit<100 OR false_claims>0 ORDER BY credit,id')]
            return {'stats': stats, 'categories': categories, 'users': users, 'violations': [dict(r) for r in s.db.execute('SELECT * FROM ledger WHERE delta<0 ORDER BY id DESC LIMIT 100')], 'policy': s.policy}

    @app.post('/v1/admin/policy')
    def policy(body: Policy, user=Depends(admin)):
        with service() as s:
            s.policy = validate_policy(body.model_dump()); s.db.execute("INSERT OR REPLACE INTO config VALUES ('policy',?)", (encode(s.policy),)); s.auto_match()
            return s.policy

    @app.post('/v1/admin/violations')
    def violate(body: Violation, user=Depends(admin)):
        with service() as s:
            s.user(body.userId); s.credit(body.userId, body.kind, body.reasonId, user['id'])
            return s.profile(body.userId)

    return app


def app_factory(): return create_app()
