"""Pure matching/validation rules. The server never trusts client scores or roles."""
import base64
import hashlib
import hmac
import io
import math
import re
import unicodedata

import jieba
from PIL import Image

DAY = 86400000
CATEGORIES = ['校园卡', '证件', '书籍', '雨伞', '水杯', '钥匙', '手机', '电脑', '背包', '耳机', '其它']
STATES = ['待匹配', '已匹配待确认', '认领申请中', '凭证核验中', '竞领中', '已完成', '已关闭', '申诉中']
DEFAULT = {'weights': {'place': .30, 'time': .20, 'ocr': .25, 'text': .20, 'color': .05},
           'threshold': .62, 'windowHours': 168, 'matchHours': 48, 'appealHours': 48,
           'creditFloor': 60, 'banCount': 2,
           'credit': {'complete': 5, 'no_show': -10, 'false_post': -15, 'false_claim': -40, 'malicious_appeal': -20}}
ALIASES = {'图书馆': '图书馆', '图书馆门口': '图书馆', '图书馆正门': '图书馆', '图书馆北门': '图书馆北门',
           '一饭': '第一食堂', '第一食堂': '第一食堂', '二饭': '第二食堂', '第二食堂': '第二食堂',
           '教学楼': '教学楼', '教学楼A栋': '教学楼A栋', 'A栋': '教学楼A栋', '宿舍': '宿舍', '操场': '操场'}
STOP = {'的', '了', '在', '一个', '一张', '一把', '丢失', '捡到', '拾获', '发现', '我', '今天', '昨天', '请', '物品'}


class DomainError(Exception):
    def __init__(self, code, message, status=409):
        self.code, self.message, self.status = code, message, status
        super().__init__(message)


def require(condition, code, message, status=409):
    if not condition:
        raise DomainError(code, message, status)


def norm(value):
    return re.sub(r'[\W_]+', '', unicodedata.normalize('NFKC', value).lower())


def tokens(value):
    return {norm(t) for t in jieba.lcut(value) if norm(t) and norm(t) not in STOP}


def jaccard(a, b):
    return len(a & b) / len(a | b) if a | b else 0.0


def secret_hash(value, key):
    return hmac.new(key.encode(), norm(value).encode(), hashlib.sha256).hexdigest()


def credential_hash(value, key):
    return hmac.new(key.encode(), value.encode(), hashlib.sha256).hexdigest()


def image_bytes(encoded):
    try:
        data = base64.b64decode(encoded, validate=True)
        require(0 < len(data) <= 1500000, 'INVALID_IMAGE', '图片需小于1.5MB', 422)
        with Image.open(io.BytesIO(data)) as im:
            require(im.format in ['JPEG', 'PNG'] and im.width * im.height <= 16000000,
                    'INVALID_IMAGE', '只接受1600万像素以内JPEG/PNG', 422)
            im.verify()
        return data
    except DomainError:
        raise
    except Exception:
        raise DomainError('INVALID_IMAGE', '图片无法解码，请重新选图', 422)


def location_similarity(a, b):
    a, b = ALIASES.get(a.strip(), a.strip()), ALIASES.get(b.strip(), b.strip())
    if not a or not b:
        return 0
    if a == b:
        return 1.0
    if a in b or b in a:
        return .8
    if {a, b} <= {'第一食堂', '第二食堂'}:
        return .5
    if '教学楼' in a and '教学楼' in b:
        return .65
    return 0.0


def score(lost, found, policy):
    gap = found['occurredAt'] - lost['occurredAt']
    window = policy['windowHours'] * 3600000
    eligible = lost['category'] == found['category'] and 0 <= gap <= window
    factors = {'place': location_similarity(lost['place'], found['place']),
               'time': max(0, 1 - gap / window) if gap >= 0 else 0,
               'ocr': jaccard(tokens(lost.get('ocrText', '')), tokens(found.get('ocrText', ''))),
               'text': jaccard(tokens(lost['description']), tokens(found['description'])),
               'color': float(bool(lost['color']) and lost['color'] == found['color'])}
    return {'eligible': eligible, 'score': round(sum(policy['weights'][k] * factors[k] for k in factors), 4) if eligible else 0,
            'factors': {k: round(v, 4) for k, v in factors.items()}}


def identifiers(value):
    return set(re.findall(r'\d{6,20}|[A-Za-z]{1,4}\d{4,15}', value))


def evidence(level, text, picture, protected_ocr):
    require(level in [1, 2, 3], 'INVALID_EVIDENCE', '证据等级应为L1、L2或L3', 422)
    require(len(text.strip()) >= 2, 'INVALID_EVIDENCE', '请填写证据说明', 422)
    if level >= 2:
        require(bool(identifiers(text) & identifiers(protected_ocr)), 'OCR_EVIDENCE_MISMATCH', '证据编号与物品受保护OCR线索不吻合', 422)
    if level == 3:
        require(bool(picture), 'EVIDENCE_IMAGE_REQUIRED', 'L3须提交证件照片及OCR文字', 422)
        image_bytes(picture)


def validate_policy(data):
    require(set(data['weights']) == set(DEFAULT['weights']), 'INVALID_POLICY', '须提供五个匹配权重', 422)
    require(all(math.isfinite(v) and 0 <= v <= 1 for v in data['weights'].values()) and
            abs(sum(data['weights'].values()) - 1) < .00001, 'INVALID_POLICY', '五项权重之和必须为1', 422)
    require(0 <= data['threshold'] <= 1 and 1 <= data['windowHours'] <= 720 and 1 <= data['matchHours'] <= 720 and
            1 <= data['appealHours'] <= 720 and 0 <= data['creditFloor'] <= 100 and 1 <= data['banCount'] <= 10,
            'INVALID_POLICY', '策略数值超出范围', 422)
    require(set(data['credit']) == set(DEFAULT['credit']) and 0 <= data['credit']['complete'] <= 20 and
            all(-100 <= v <= 0 for k, v in data['credit'].items() if k != 'complete'), 'INVALID_POLICY', '信用分幅度无效', 422)
    return data
