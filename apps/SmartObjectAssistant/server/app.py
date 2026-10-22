"""Device-scoped records, JWT authentication and versioned model delivery."""
import base64
from contextlib import contextmanager
import hashlib
import hmac
import json
import os
from pathlib import Path
import sqlite3
import time
from typing import Annotated, Iterator

import jwt
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, ConfigDict, model_validator

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / '.local'


@contextmanager
def connect(path: Path) -> Iterator[sqlite3.Connection]:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, key_hash TEXT NOT NULL)')
    db.execute('''CREATE TABLE IF NOT EXISTS records (
        device TEXT NOT NULL, id TEXT NOT NULL, captured INTEGER NOT NULL,
        revision INTEGER NOT NULL, payload TEXT NOT NULL, digest TEXT NOT NULL,
        PRIMARY KEY(device,id))''')
    db.execute('CREATE INDEX IF NOT EXISTS records_time ON records(device,captured)')
    db.commit()
    try:
        with db:
            yield db
    finally:
        db.close()


def key_digest(key: str) -> str:
    # Provisioned keys are 32 random bytes, not human passwords.
    return hashlib.sha256(key.encode()).hexdigest()


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class Credentials(StrictModel):
    deviceId: str = Field(min_length=3, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    deviceKey: str = Field(min_length=16, max_length=200)


class Item(StrictModel):
    id: str = Field(min_length=1, max_length=80)
    classId: int = Field(ge=-1, le=79)
    name: str = Field(min_length=1, max_length=50)
    score: float = Field(ge=0, le=1)
    x1: float = Field(ge=0)
    y1: float = Field(ge=0)
    x2: float = Field(gt=0)
    y2: float = Field(gt=0)


class Record(StrictModel):
    recordId: str = Field(min_length=5, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    capturedAt: int = Field(ge=0, le=32503680000000)
    updatedAt: int = Field(ge=0, le=32503680000000)
    revision: int = Field(ge=1, le=2147483647)
    width: int = Field(ge=1, le=20000)
    height: int = Field(ge=1, le=20000)
    modelVersion: str = Field(min_length=1, max_length=60)
    threshold: float = Field(ge=0, le=1)
    items: list[Item] = Field(max_length=100)
    thumbnailBase64: str = Field(max_length=200000)

    @model_validator(mode='after')
    def validate_image_and_boxes(self) -> 'Record':
        try:
            data = base64.b64decode(self.thumbnailBase64, validate=True)
        except (ValueError, base64.binascii.Error):
            raise ValueError('thumbnailBase64 must be valid base64')
        if not data.startswith(b'\xff\xd8\xff') or len(data) > 150000:
            raise ValueError('thumbnail must be JPEG and at most 150 KB')
        if len({item.id for item in self.items}) != len(self.items):
            raise ValueError('duplicate item id')
        for item in self.items:
            if not (item.x1 < item.x2 <= self.width and item.y1 < item.y2 <= self.height):
                raise ValueError('bounding box is outside the original image')
        if self.updatedAt < self.capturedAt:
            raise ValueError('updatedAt precedes capturedAt')
        return self


class Batch(StrictModel):
    records: list[Record] = Field(min_length=1, max_length=20)


def create_app(db_path: Path | None = None, signing_key: str | None = None,
               manifest_path: Path | None = None, token_ttl: int = 300) -> FastAPI:
    database = db_path or LOCAL / 'records.db'
    key_file = LOCAL / 'jwt-secret.txt'
    key = signing_key or os.getenv('LAB3_JWT_SECRET') or (key_file.read_text().strip() if key_file.exists() else '')
    if len(key) < 32:
        raise RuntimeError('Run python -m server.manage init to create a private signing key.')
    manifest = manifest_path or LOCAL / 'model.json'
    with connect(database):
        pass
    app = FastAPI(title='Smart Objects API', version='1.0.0')
    bearer = HTTPBearer(auto_error=False)

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, error: HTTPException) -> JSONResponse:
        detail = error.detail if isinstance(error.detail, dict) else {'code': 'REQUEST_ERROR', 'message': str(error.detail)}
        return JSONResponse(status_code=error.status_code, content={'error': detail}, headers=error.headers)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, error: RequestValidationError) -> JSONResponse:
        # Never echo request bodies containing credentials or pictures.
        return JSONResponse(status_code=422, content={'error': {'code': 'VALIDATION_ERROR', 'message': '请求字段或图片、检测框格式不正确。'}})

    @app.middleware('http')
    async def limit_body(request: Request, call_next):
        # Bound streamed requests too; Content-Length alone cannot prevent chunked oversized bodies.
        if request.method in {'POST', 'PUT', 'PATCH'}:
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > 4500000:
                    return JSONResponse(status_code=413, content={'error': {'code': 'BODY_TOO_LARGE', 'message': '一次最多上传20条小图记录。'}})
            request._body = bytes(body)
        return await call_next(request)

    def current_device(auth: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]) -> str:
        try:
            if auth is None or auth.scheme.lower() != 'bearer':
                raise jwt.InvalidTokenError('missing token')
            claims = jwt.decode(auth.credentials, key, algorithms=['HS256'], audience='smart-objects',
                                issuer='smart-objects-api', options={'require': ['exp', 'iat', 'sub', 'aud', 'iss']})
            device = claims['sub']
            with connect(database) as db:
                if not db.execute('SELECT 1 FROM devices WHERE id=?', (device,)).fetchone():
                    raise jwt.InvalidTokenError('device revoked')
            return device
        except jwt.InvalidTokenError:
            raise HTTPException(401, {'code': 'AUTH_REQUIRED', 'message': '令牌缺失或过期，请重新鉴权。'}, headers={'WWW-Authenticate': 'Bearer'})

    device_dependency = Annotated[str, Depends(current_device)]

    @app.get('/health')
    def health():
        return {'status': 'ok', 'service': 'smart-objects'}

    @app.post('/v1/auth/token')
    def token(credentials: Credentials):
        with connect(database) as db:
            row = db.execute('SELECT key_hash FROM devices WHERE id=?', (credentials.deviceId,)).fetchone()
        # Perform the same digest comparison even for unknown devices.
        expected = row['key_hash'] if row else '0' * 64
        if not hmac.compare_digest(key_digest(credentials.deviceKey), expected):
            raise HTTPException(401, {'code': 'DEVICE_REJECTED', 'message': '设备标识或密钥不正确。'})
        now = int(time.time())
        access_token = jwt.encode({'sub': credentials.deviceId, 'iat': now, 'exp': now + token_ttl,
                                   'aud': 'smart-objects', 'iss': 'smart-objects-api'}, key, algorithm='HS256')
        return {'accessToken': access_token, 'expiresIn': token_ttl, 'tokenType': 'Bearer'}

    @app.post('/v1/records/batch')
    def upload(batch: Batch, device: device_dependency):
        if len({record.recordId for record in batch.records}) != len(batch.records):
            raise HTTPException(422, {'code': 'DUPLICATE_BATCH_ID', 'message': '同一批次不能包含重复记录标识。'})
        accepted = []
        with connect(database) as db:
            db.execute('BEGIN IMMEDIATE')
            for record in batch.records:
                payload = json.dumps(record.model_dump(), ensure_ascii=False, sort_keys=True, separators=(',', ':'))
                digest = hashlib.sha256(payload.encode()).hexdigest()
                row = db.execute('SELECT revision,digest FROM records WHERE device=? AND id=?', (device, record.recordId)).fetchone()
                if row and row['revision'] == record.revision and row['digest'] != digest:
                    raise HTTPException(409, {'code': 'REVISION_CONFLICT', 'message': '同一版本内容不同，请保存编辑后重新同步。'})
                status = 'duplicate' if row else 'created'
                if not row or record.revision > row['revision']:
                    status = 'updated' if row else 'created'
                    db.execute('INSERT OR REPLACE INTO records VALUES (?,?,?,?,?,?)',
                               (device, record.recordId, record.capturedAt, record.revision, payload, digest))
                elif row['revision'] > record.revision:
                    status = 'stale'
                accepted.append({'recordId': record.recordId, 'revision': record.revision, 'status': status})
        return {'accepted': accepted}

    def query_records(device: str, start: int, end: int, category: str) -> list[dict]:
        if start > end:
            raise HTTPException(422, {'code': 'INVALID_TIME_RANGE', 'message': '开始时间应早于结束时间。'})
        with connect(database) as db:
            rows = db.execute('SELECT payload FROM records WHERE device=? AND captured>=? AND captured<=? ORDER BY captured DESC,id',
                              (device, start, end)).fetchall()
        records = [json.loads(row['payload']) for row in rows]
        return [r for r in records if not category or any(category.casefold() in item['name'].casefold() for item in r['items'])]

    @app.get('/v1/records')
    def records(device: device_dependency, start: int = Query(0, ge=0), end: int = Query(32503680000000, ge=0),
                category: str = Query('', max_length=50), page: int = Query(1, ge=1, le=1000000),
                pageSize: int = Query(10, ge=1, le=100)):
        rows = query_records(device, start, end, category.strip())
        offset = (page - 1) * pageSize
        return {'records': rows[offset:offset + pageSize], 'total': len(rows), 'page': page, 'pageSize': pageSize}

    @app.get('/v1/statistics')
    def statistics(device: device_dependency, start: int = Query(0, ge=0), end: int = Query(32503680000000, ge=0),
                   category: str = Query('', max_length=50)):
        records = query_records(device, start, end, category.strip())
        counts: dict[str, int] = {}
        for record in records:
            for item in record['items']:
                if not category or category.strip().casefold() in item['name'].casefold():
                    counts[item['name']] = counts.get(item['name'], 0) + 1
        return {'recordCount': len(records), 'objectCount': sum(counts.values()),
                'categories': [{'name': name, 'count': count} for name, count in sorted(counts.items(), key=lambda x: (-x[1], x[0]))]}

    def read_model() -> tuple[dict, Path]:
        try:
            data = json.loads(manifest.read_text(encoding='utf-8'))
            file = Path(data['path']).resolve()
            if not file.is_file():
                raise ValueError('missing model')
            return data, file
        except (OSError, KeyError, ValueError):
            raise HTTPException(503, {'code': 'MODEL_UNAVAILABLE', 'message': '模型尚未发布，请稍后重试。'})

    @app.get('/v1/models/latest')
    def latest_model(device: device_dependency):
        data, file = read_model()
        return {'version': data['version'], 'sha256': data['sha256'], 'size': data['size'],
                'inputSize': 640, 'downloadUrl': f"/v1/models/{data['version']}/file"}

    @app.get('/v1/models/{version}/file')
    def model_file(version: str, device: device_dependency):
        data, file = read_model()
        if version != data['version']:
            raise HTTPException(404, {'code': 'MODEL_VERSION_NOT_FOUND', 'message': '模型版本已更新，请重新检查。'})
        return FileResponse(file, media_type='application/octet-stream', filename='yolov13n.onnx', headers={'ETag': data['sha256']})

    return app


def app_factory() -> FastAPI:
    return create_app()
