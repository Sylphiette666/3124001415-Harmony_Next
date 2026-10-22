import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import time

from fastapi.testclient import TestClient
import jwt
import pytest

from server.app import connect, create_app, key_digest


@pytest.fixture
def service(tmp_path):
    database = tmp_path / 'test.db'
    with connect(database) as db:
        for device in ['device-a', 'device-b']:
            db.execute('INSERT INTO devices VALUES (?,?)', (device, key_digest('a-private-random-test-device-key')))
    model = tmp_path / 'model.onnx'
    model.write_bytes(b'test-model-file')
    manifest = tmp_path / 'model.json'
    manifest.write_text(json.dumps({'version': '1.0.1', 'path': str(model), 'size': model.stat().st_size,
                                    'sha256': hashlib.sha256(model.read_bytes()).hexdigest()}))
    key = 'a-long-private-signing-key-for-tests-only-123456789'
    app = create_app(database, key, manifest)
    client = TestClient(app)
    return client, database, key, model


def token(client, device='device-a'):
    response = client.post('/v1/auth/token', json={'deviceId': device, 'deviceKey': 'a-private-random-test-device-key'})
    assert response.status_code == 200
    return {'Authorization': 'Bearer ' + response.json()['accessToken']}


def record(id='scan-0001', category='水杯', captured=1000):
    return {'recordId': id, 'capturedAt': captured, 'updatedAt': captured, 'revision': 1, 'width': 800, 'height': 600,
            'modelVersion': '1.0.0', 'threshold': 0.35,
            'items': [{'id': 'box-1', 'classId': 41, 'name': category, 'score': 0.9, 'x1': 10, 'y1': 20, 'x2': 100, 'y2': 200}],
            'thumbnailBase64': base64.b64encode(b'\xff\xd8\xff\xe0sample-jpeg-for-contract-test').decode()}


def upload(client, headers, records):
    return client.post('/v1/records/batch', headers=headers, json={'records': records})


def test_requires_auth_and_rejects_bad_key(service):
    client, *_ = service
    for path in ['/v1/records', '/v1/statistics', '/v1/models/latest', '/v1/models/1.0.1/file']:
        response = client.get(path)
        assert response.status_code == 401
        assert response.json()['error']['code'] == 'AUTH_REQUIRED'
    assert upload(client, {}, [record()]).status_code == 401
    for device in ['device-a', 'unknown-device']:
        assert client.post('/v1/auth/token', json={'deviceId': device, 'deviceKey': 'wrong-key-long-enough'}).status_code == 401


def test_expired_and_forged_tokens_rejected(service):
    client, _, key, _ = service
    for key_used, expiry in [(key, int(time.time()) - 60), ('wrong-signing-key-that-is-long-enough', int(time.time()) + 60)]:
        encoded = jwt.encode({'sub': 'device-a', 'iat': int(time.time()) - 100, 'exp': expiry,
                              'aud': 'smart-objects', 'iss': 'smart-objects-api'}, key_used, algorithm='HS256')
        assert client.get('/v1/records', headers={'Authorization': 'Bearer ' + encoded}).status_code == 401
    assert client.get('/v1/records', headers=token(client)).status_code == 200


def test_idempotence_and_revision_update(service):
    client, *_ = service
    headers = token(client)
    assert upload(client, headers, [record()]).json()['accepted'][0]['status'] == 'created'
    assert upload(client, headers, [record()]).json()['accepted'][0]['status'] == 'duplicate'
    changed = record(); changed['items'][0]['name'] = '修正后的水杯'
    assert upload(client, headers, [changed]).status_code == 409
    changed['revision'] = 2; changed['updatedAt'] = 2000
    assert upload(client, headers, [changed]).json()['accepted'][0]['status'] == 'updated'
    assert upload(client, headers, [record()]).json()['accepted'][0]['status'] == 'stale'
    data = client.get('/v1/records', headers=headers).json()
    assert data['total'] == 1 and data['records'][0]['revision'] == 2
    assert client.get('/v1/statistics', headers=headers).json()['objectCount'] == 1


def test_device_isolation_filters_and_pagination(service):
    client, *_ = service
    a, b = token(client), token(client, 'device-b')
    assert upload(client, a, [record('scan-0001', '水杯', 1000), record('scan-0002', '手机', 2000), record('scan-0003', '水杯', 3000)]).status_code == 200
    assert upload(client, b, [record('scan-0001', '键盘', 3000)]).status_code == 200
    assert client.get('/v1/records', headers=b).json()['total'] == 1
    filtered = client.get('/v1/records?category=水杯&start=1000&end=3000&page=2&pageSize=1', headers=a).json()
    assert filtered['total'] == 2 and filtered['records'][0]['capturedAt'] == 1000
    stats = client.get('/v1/statistics?category=水杯&start=2000&end=3000', headers=a).json()
    assert stats == {'recordCount': 1, 'objectCount': 1, 'categories': [{'name': '水杯', 'count': 1}]}
    assert client.get('/v1/records?category=%27%20OR%201=1--', headers=a).json()['total'] == 0
    assert client.get('/v1/records?start=9&end=1', headers=a).status_code == 422


def test_batch_transaction_rolls_back_on_conflict(service):
    client, *_ = service
    headers = token(client)
    upload(client, headers, [record('existing-record')])
    conflict = record('existing-record'); conflict['items'][0]['name'] = '冲突'
    assert upload(client, headers, [record('new-record-1'), conflict]).status_code == 409
    assert client.get('/v1/records', headers=headers).json()['total'] == 1


def test_parallel_retries_do_not_duplicate(service):
    client, *_ = service
    headers = token(client)
    with ThreadPoolExecutor(max_workers=4) as pool:
        statuses = list(pool.map(lambda _: upload(client, headers, [record()]).status_code, range(8)))
    assert statuses == [200] * 8
    assert client.get('/v1/records', headers=headers).json()['total'] == 1


def test_model_manifest_and_authenticated_download(service):
    client, _, _, model = service
    headers = token(client)
    data = client.get('/v1/models/latest', headers=headers).json()
    response = client.get(data['downloadUrl'], headers=headers)
    assert response.status_code == 200 and response.content == model.read_bytes()
    assert hashlib.sha256(response.content).hexdigest() == data['sha256']
    assert len(response.content) == data['size']
    assert client.get('/v1/models/obsolete/file', headers=headers).status_code == 404


def test_invalid_payloads_are_rejected_without_echoing_secrets(service):
    client, *_ = service
    headers = token(client)
    for bad in [dict(record(), thumbnailBase64='not-base64'), dict(record(), width=1), dict(record(), threshold=5),
                dict(record(), revision=0)]:
        response = upload(client, headers, [bad]); assert response.status_code == 422
        assert response.json()['error']['code'] == 'VALIDATION_ERROR'
    assert upload(client, headers, [record(), record()]).status_code == 422
    response = client.post('/v1/auth/token', json={'deviceId': 'a', 'deviceKey': 'private-test-secret'})
    assert 'private-test-secret' not in response.text


def test_body_limit(service):
    client, *_ = service
    response = client.post('/v1/records/batch', content=b'x' * 4500001, headers={'Content-Type': 'application/json'})
    assert response.status_code == 413


def test_published_version_cannot_change_bytes(tmp_path, monkeypatch):
    from server import manage
    import sys
    monkeypatch.setattr(manage, 'LOCAL', tmp_path / 'private')
    model = tmp_path / 'model.onnx'
    model.write_bytes(b'A' * 1200)
    monkeypatch.setattr(sys, 'argv', ['manage', 'publish', '--version', '1.0.0', '--file', str(model)])
    manage.main()
    original = (manage.LOCAL / 'model.json').read_bytes()
    manage.main()  # Identical bytes may be republished.
    model.write_bytes(b'B' * 1200)
    with pytest.raises(SystemExit) as failure:
        manage.main()
    assert failure.value.code == 2
    assert (manage.LOCAL / 'model.json').read_bytes() == original
    assert (manage.LOCAL / 'models/yolov13n-1.0.0.onnx').read_bytes() == b'A' * 1200
