import hashlib
import json
import time
import uuid

from .database import encode
from .engine import DEFAULT, DAY, DomainError, require, score, secret_hash, evidence

ACTIVE = ['已匹配待确认', '认领申请中', '凭证核验中', '竞领中']


class Service:
    def __init__(self, db, key, clock=None):
        self.db, self.key = db, key
        self.now = int((clock or (lambda: time.time() * 1000))())
        row = db.execute("SELECT data FROM config WHERE key='policy'").fetchone()
        self.policy = json.loads(row[0]) if row else json.loads(json.dumps(DEFAULT))

    def user(self, id):
        r = self.db.execute('SELECT * FROM users WHERE id=?', (id,)).fetchone()
        require(r is not None, 'USER_NOT_FOUND', '用户不存在', 404)
        return dict(r)

    def profile(self, id):
        u = self.user(id)
        return {k: u[k] for k in ['id', 'name', 'role', 'credit', 'false_claims']} | {'banned': u['false_claims'] >= self.policy['banCount'], 'creditFloor': self.policy['creditFloor']}

    def item(self, id):
        r = self.db.execute('SELECT * FROM items WHERE id=?', (id,)).fetchone()
        require(r is not None, 'ITEM_NOT_FOUND', '物品不存在', 404)
        return dict(r) | {'payload': json.loads(r['data'])}

    def match(self, id):
        r = self.db.execute('SELECT * FROM matches WHERE id=?', (id,)).fetchone()
        require(r is not None, 'MATCH_NOT_FOUND', '匹配记录不存在', 404)
        return dict(r)

    def touch(self, item_id, state):
        self.db.execute('UPDATE items SET state=?,version=version+1 WHERE id=?', (state, item_id))
        self.db.execute('INSERT INTO changes(item_id) VALUES (?)', (item_id,))

    def event(self, match_id, actor, state, message):
        self.db.execute('INSERT INTO events(match_id,actor,state,message,created) VALUES (?,?,?,?,?)',
                        (match_id, actor, state, message, self.now))

    def notify(self, user, message):
        self.db.execute('INSERT INTO notifications(user_id,message,created) VALUES (?,?,?)', (user, message, self.now))

    def credit(self, user, kind, reason, actor):
        delta = self.policy['credit'][kind]
        cursor = self.db.execute('INSERT OR IGNORE INTO ledger(user_id,kind,delta,reason_id,actor,created) VALUES (?,?,?,?,?,?)',
                                 (user, kind, delta, reason, actor, self.now))
        if cursor.rowcount:
            self.db.execute('UPDATE users SET credit=MIN(150,MAX(0,credit+?)),false_claims=false_claims+? WHERE id=?',
                            (delta, int(kind == 'false_claim'), user))
            self.notify(user, f'信用分变动 {delta:+d}，原因：{kind}')

    def public_item(self, id, viewer):
        r = self.item(id); p = r['payload']; own = viewer['id'] == r['owner'] or viewer['role'] == 'admin'
        hidden_photo = p['category'] in ['校园卡', '证件'] and not own
        return {k: p[k] for k in ['itemId', 'kind', 'category', 'color', 'place', 'occurredAt', 'description', 'question']} | {
            'ownerId': r['owner'], 'ownerName': self.user(r['owner'])['name'], 'state': r['state'], 'version': r['version'],
            'description': f"{p['color']}{p['category']}，于{p['place']}登记（详细描述仅本人和平台可见）" if hidden_photo else p['description'],
            'ocrText': p['ocrText'] if own else '', 'ocrHint': '含受保护文字线索' if p['ocrText'] else '无文字线索',
            'imageBase64': '' if hidden_photo else p['imageBase64'], 'imagePrivate': hidden_photo,
            'completedMatchId': (self.db.execute("SELECT id FROM matches WHERE found=? AND state IN ('已完成','申诉中') LIMIT 1", (id,)).fetchone() or [''])[0]}

    def publish(self, actor, payload):
        require(payload['occurredAt'] <= self.now + 300000, 'FUTURE_TIME', '物品时间不能晚于当前时间', 422)
        digest = hashlib.sha256(encode(payload).encode()).hexdigest()
        old = self.db.execute('SELECT * FROM items WHERE id=?', (payload['itemId'],)).fetchone()
        if old:
            require(old['owner'] == actor['id'] and old['digest'] == digest, 'IDEMPOTENCY_CONFLICT', 'itemId已存在且内容不同')
            return {'itemId': old['id'], 'status': 'duplicate'}
        require(actor['credit'] >= self.policy['creditFloor'], 'CREDIT_PUBLISH_BLOCKED', '信用分低于发布门槛，请联系管理员', 403)
        stored = dict(payload); answer = stored.pop('answer')
        self.db.execute('INSERT INTO items(id,owner,kind,data,digest,answer_hash,state) VALUES (?,?,?,?,?,?,?)',
                        (payload['itemId'], actor['id'], payload['kind'], encode(stored), digest,
                         secret_hash(answer, self.key) if answer else '', '待匹配'))
        self.db.execute('INSERT INTO changes(item_id) VALUES (?)', (payload['itemId'],))
        self.auto_match()
        return {'itemId': payload['itemId'], 'status': 'created'}

    def create_match(self, lost, found, actor, automatic=False):
        require(lost['kind'] == 'lost' and found['kind'] == 'found' and lost['owner'] != found['owner'], 'PAIR_INVALID', '失物与招领类型或所有者不符合条件', 422)
        require(lost['state'] not in ['已完成', '已关闭', '申诉中'] and found['state'] not in ['已完成', '已关闭', '申诉中'], 'ITEM_UNAVAILABLE', '物品当前不可匹配')
        result = score(lost['payload'], found['payload'], self.policy)
        require(result['eligible'], 'PAIR_INELIGIBLE', '类别不一致或时间窗不吻合', 422)
        old = self.db.execute('SELECT * FROM matches WHERE lost=? AND found=?', (lost['id'], found['id'])).fetchone()
        if old:
            require(old['state'] != '已关闭', 'MATCH_CLOSED', '此匹配已关闭，请提交新登记或联系管理员')
            return dict(old)
        locked = self.db.execute("SELECT * FROM matches WHERE found=? AND state NOT IN ('已完成','已关闭') ORDER BY score DESC LIMIT 1", (found['id'],)).fetchone()
        if locked and result['score'] > locked['score'] and actor != 'claim':
            raise DomainError('MATCH_LOCKED', '已有匹配已锁定，新高分候选不自动替换；可通过竞领流程申请')
        id = str(uuid.uuid4())
        self.db.execute('INSERT INTO matches(id,lost,found,score,state,created,deadline) VALUES (?,?,?,?,?,?,?)',
                        (id, lost['id'], found['id'], result['score'], '已匹配待确认', self.now, self.now + self.policy['matchHours'] * 3600000))
        self.touch(lost['id'], '已匹配待确认'); self.touch(found['id'], '已匹配待确认')
        self.event(id, actor, '已匹配待确认', f'{"自动" if automatic else "手动"}建立匹配，分数 {result["score"]:.2f}')
        self.notify(lost['owner'], '发现匹配候选，可查看评分并申请认领')
        self.notify(found['owner'], '招领物品已产生匹配候选')
        return self.match(id)

    def auto_match(self):
        lost = [self.item(r[0]) for r in self.db.execute("SELECT id FROM items WHERE kind='lost' AND state IN ('待匹配','已匹配待确认')")]
        for row in list(self.db.execute("SELECT id FROM items WHERE kind='found' AND state IN ('待匹配','已匹配待确认')")):
            found = self.item(row[0])
            candidates = [(score(l['payload'], found['payload'], self.policy), l) for l in lost if l['owner'] != found['owner']]
            candidates = [c for c in candidates if c[0]['eligible'] and c[0]['score'] >= self.policy['threshold']]
            candidates.sort(key=lambda c: (-c[0]['score'], c[1]['id']))
            if candidates:
                try: self.create_match(candidates[0][1], found, 'system', True)
                except DomainError as e:
                    if e.code not in ['MATCH_LOCKED', 'MATCH_CLOSED', 'ITEM_UNAVAILABLE']: raise

    def candidates(self, actor, lost_id):
        lost = self.item(lost_id)
        require(lost['owner'] == actor['id'] or actor['role'] == 'admin', 'FORBIDDEN', '只能为自己的失物查询候选', 403)
        require(lost['kind'] == 'lost', 'PAIR_INVALID', '请选择失物登记', 422)
        result = []
        for row in self.db.execute("SELECT id FROM items WHERE kind='found' AND state NOT IN ('已完成','已关闭','申诉中')"):
            found = self.item(row[0])
            if found['owner'] == lost['owner']: continue
            rating = score(lost['payload'], found['payload'], self.policy)
            if rating['eligible']: result.append({'item': self.public_item(found['id'], actor), **rating, 'automatic': rating['score'] >= self.policy['threshold']})
        return sorted(result, key=lambda r: (-r['score'], r['item']['itemId']))

    def advance(self, found_id):
        if not self.db.execute("SELECT 1 FROM claims WHERE found=? AND state='核验中'", (found_id,)).fetchone():
            next_row = self.db.execute("SELECT * FROM claims WHERE found=? AND state='排队' ORDER BY created,id LIMIT 1", (found_id,)).fetchone()
            if next_row:
                self.db.execute("UPDATE claims SET state='核验中' WHERE id=?", (next_row['id'],))
                self.event(next_row['match_id'], 'system', '凭证核验中', '队列轮到本申请，等待回答凭证问题')
                self.notify(next_row['user_id'], '已轮到您核验，请回答凭证问题')
        rows = list(self.db.execute("SELECT * FROM claims WHERE found=? AND state IN ('排队','核验中','已通过')", (found_id,)))
        state = '竞领中' if len(rows) > 1 else '凭证核验中' if any(r['state'] == '核验中' for r in rows) else '认领申请中' if rows else '已匹配待确认'
        for m in list(self.db.execute("SELECT * FROM matches WHERE found=? AND state NOT IN ('已完成','已关闭','申诉中')", (found_id,))):
            self.db.execute('UPDATE matches SET state=? WHERE id=?', (state, m['id']))
            self.touch(m['lost'], state)
        self.touch(found_id, state)

    def claim(self, actor, lost_id, found_id):
        require(actor['false_claims'] < self.policy['banCount'], 'CLAIM_BANNED', '冒领违规达到上限，禁止认领，请联系管理员', 403)
        lost, found = self.item(lost_id), self.item(found_id)
        require(lost['owner'] == actor['id'] and found['owner'] != actor['id'], 'FORBIDDEN', '只能为自己的失物申请，不能认领自己的招领', 403)
        m = self.create_match(lost, found, 'claim')
        old = self.db.execute('SELECT * FROM claims WHERE found=? AND user_id=?', (found_id, actor['id'])).fetchone()
        if old:
            if old['state'] == '已关闭' and m['priority_user'] == actor['id']:
                self.db.execute("UPDATE claims SET state='排队',match_id=?,created=?,score=0,level=1,answer='',evidence='',image='' WHERE id=?", (m['id'], self.now - 1, old['id']))
            else:
                require(old['state'] != '已关闭', 'CLAIM_CLOSED', '该认领申请已关闭')
                return {'claimId': old['id'], 'state': old['state']}
            id = old['id']
        else:
            id = str(uuid.uuid4())
            self.db.execute('INSERT INTO claims(id,match_id,found,user_id,state,created) VALUES (?,?,?,?,?,?)', (id, m['id'], found_id, actor['id'], '排队', self.now))
        self.event(m['id'], actor['id'], '认领申请中', '提交认领申请，进入串行核验队列')
        self.advance(found_id)
        return {'claimId': id, 'state': self.db.execute('SELECT state FROM claims WHERE id=?', (id,)).fetchone()[0]}

    def answer(self, actor, claim_id, payload):
        row = self.db.execute('SELECT * FROM claims WHERE id=?', (claim_id,)).fetchone()
        require(row is not None, 'CLAIM_NOT_FOUND', '认领申请不存在', 404)
        require(row['user_id'] == actor['id'], 'FORBIDDEN', '不能回答他人的凭证问题', 403)
        require(row['state'] == '核验中', 'INVALID_TRANSITION', '仅轮到核验的申请可以作答')
        found = self.item(row['found']); level = payload['level']
        if level > 1: evidence(level, payload['evidenceText'], payload['evidenceImage'], found['payload']['ocrText'])
        self.db.execute('UPDATE claims SET answer=?,evidence=?,image=?,level=? WHERE id=?',
                        (payload['answer'], payload['evidenceText'], payload['evidenceImage'], level, claim_id))
        if level > 1:
            self.event(row['match_id'], actor['id'], '凭证核验中', f'提交L{level}材料，等待发布者审核；不能自行提升证据等级')
            self.notify(found['owner'], '有高等级凭证材料待审核')
            return {'state': '核验中', 'message': '材料已提交，请等待发布者审核'}
        passed = secret_hash(payload['answer'], self.key) == found['answer_hash']
        return self.finish_verification(row, passed, 100 if passed else 0, 1, actor['id'])

    def finish_verification(self, row, passed, rating, level, actor):
        self.db.execute('UPDATE claims SET state=?,score=?,level=? WHERE id=?', ('已通过' if passed else '已关闭', rating if passed else 0, level, row['id']))
        if not passed:
            self.db.execute("UPDATE matches SET state='已关闭' WHERE id=?", (row['match_id'],)); self.touch(self.match(row['match_id'])['lost'], '待匹配')
        self.event(row['match_id'], actor, '认领申请中' if passed else '已关闭', f'凭证核验{"通过" if passed else "失败"}，得分 {rating if passed else 0}，L{level}')
        self.notify(row['user_id'], '凭证通过，等待队列核验完毕后择优确认' if passed else '凭证未通过，申请已拒绝，队列已释放')
        self.advance(row['found'])
        return {'state': '已通过' if passed else '已关闭', 'message': '核验通过' if passed else '核验失败，已关闭并释放队列'}

    def review(self, actor, claim_id, payload):
        row = self.db.execute('SELECT * FROM claims WHERE id=?', (claim_id,)).fetchone()
        require(row is not None, 'CLAIM_NOT_FOUND', '申请不存在', 404)
        require(actor['role'] == 'admin' or self.item(row['found'])['owner'] == actor['id'], 'FORBIDDEN', '只有发布者或管理员可审核', 403)
        require(row['state'] == '核验中' and bool(row['answer']), 'INVALID_TRANSITION', '当前没有可审核的作答材料')
        require(not payload['passed'] or payload['score'] >= 60, 'INVALID_SCORE', '通过审核的凭证分数须达到60分')
        if row['level'] > 1: evidence(row['level'], row['evidence'], row['image'], self.item(row['found'])['payload']['ocrText'])
        return self.finish_verification(row, payload['passed'], payload['score'], row['level'], actor['id'])

    def complete(self, actor, match_id):
        m = self.match(match_id); found = self.item(m['found'])
        require(actor['role'] == 'admin' or found['owner'] == actor['id'], 'FORBIDDEN', '只有发布者或管理员可确认领取', 403)
        require(m['state'] in ACTIVE and found['state'] not in ['已完成', '申诉中'], 'INVALID_TRANSITION', '当前状态不能确认领取')
        require(not self.db.execute("SELECT 1 FROM claims WHERE found=? AND state IN ('排队','核验中')", (m['found'],)).fetchone(), 'QUEUE_NOT_FINISHED', '竞领队列尚未完成核验，不能提前确认')
        rows = list(self.db.execute("SELECT c.*,u.credit FROM claims c JOIN users u ON c.user_id=u.id WHERE c.found=? AND c.state='已通过' ORDER BY (c.score*0.8+u.credit*0.2) DESC,c.created,c.id", (m['found'],)))
        require(bool(rows), 'PROOF_REQUIRED', '未通过凭证核验，不能直接完成')
        rows = [r for r in rows if self.item(self.match(r['match_id'])['lost'])['state'] not in ['已完成','已关闭','申诉中']]
        require(bool(rows), 'ITEM_UNAVAILABLE', '失物登记已在其他流程完成或不可用')
        winner = rows[0]; winner_match = self.match(winner['match_id'])
        for case in list(self.db.execute("SELECT * FROM matches WHERE found=? AND state NOT IN ('已关闭','已完成')", (m['found'],))):
            success = case['id'] == winner['match_id']; state = '已完成' if success else '已关闭'
            self.db.execute('UPDATE matches SET state=?,winner=? WHERE id=?', (state, winner['id'] if success else None, case['id']))
            self.touch(case['lost'], state if success else '待匹配'); self.event(case['id'], actor['id'], state, '按凭证得分80%+信用分20%择优，确认领取完成' if success else '竞领择优结束，本候选已关闭')
        for row in rows:
            self.db.execute('UPDATE claims SET state=? WHERE id=?', ('已完成' if row['id'] == winner['id'] else '已关闭', row['id']))
            self.notify(row['user_id'], '认领完成，感谢诚信领取' if row['id'] == winner['id'] else '竞领未中选，已自动拒绝；未扣除信用分')
        self.touch(m['found'], '已完成'); self.credit(winner['user_id'], 'complete', winner['id'], actor['id'])
        for other in list(self.db.execute("SELECT * FROM matches WHERE lost=? AND found<>? AND state NOT IN ('已完成','已关闭','申诉中')", (winner_match['lost'], m['found']))):
            self.db.execute("UPDATE matches SET state='已关闭' WHERE id=?", (other['id'],))
            self.db.execute("UPDATE claims SET state='已关闭' WHERE match_id=? AND state IN ('排队','核验中','已通过')", (other['id'],))
            self.event(other['id'], actor['id'], '已关闭', '同一失物已在另一流程完成，关闭重复候选')
            if self.db.execute("SELECT 1 FROM matches WHERE found=? AND state NOT IN ('已关闭','已完成')", (other['found'],)).fetchone(): self.advance(other['found'])
            else: self.touch(other['found'], '待匹配')
        return {'state': '已完成', 'winner': winner['user_id'], 'matchId': winner_match['id']}

    def appeal(self, actor, match_id, payload):
        m = self.match(match_id)
        require(m['state'] == '已完成', 'INVALID_TRANSITION', '只能对已完成的认领申诉')
        winner = self.db.execute('SELECT * FROM claims WHERE id=?', (m['winner'],)).fetchone()
        require(actor['id'] not in [winner['user_id'], self.item(m['found'])['owner']], 'FORBIDDEN', '原认领者和发布者不能对本认领发起冒领申诉', 403)
        lost = self.item(payload['lostId']); found = self.item(m['found'])
        require(lost['owner'] == actor['id'] and score(lost['payload'], found['payload'], self.policy)['eligible'], 'FORBIDDEN', '须关联自己的同类别失物登记', 403)
        require(payload['level'] > winner['level'], 'EVIDENCE_TOO_WEAK', '申诉证据等级必须高于原认领核验等级')
        evidence(payload['level'], payload['evidenceText'], payload['evidenceImage'], found['payload']['ocrText'])
        id = str(uuid.uuid4())
        self.db.execute('INSERT INTO appeals(id,match_id,user_id,level,evidence,image,state,created,deadline) VALUES (?,?,?,?,?,?,?,?,?)',
                        (id, match_id, actor['id'], payload['level'], payload['evidenceText'], payload['evidenceImage'], '待裁定', self.now, self.now + self.policy['appealHours'] * 3600000))
        self.db.execute("UPDATE matches SET state='申诉中' WHERE id=?", (match_id,)); self.touch(m['found'], '申诉中'); self.touch(m['lost'], '申诉中')
        self.event(match_id, actor['id'], '申诉中', f'受理L{payload["level"]}证据，等待发布者或平台裁定')
        self.notify(found['owner'], '有冒领申诉等待裁定'); return {'appealId': id, 'state': '申诉中'}

    def decide(self, actor, appeal_id, valid, timeout=False):
        a = self.db.execute('SELECT * FROM appeals WHERE id=?', (appeal_id,)).fetchone()
        require(a is not None, 'APPEAL_NOT_FOUND', '申诉不存在', 404)
        m = self.match(a['match_id']); found = self.item(m['found'])
        require(timeout or actor['role'] == 'admin' or found['owner'] == actor['id'], 'FORBIDDEN', '只有发布者或平台管理员可裁定', 403)
        require(a['state'] == '待裁定' and m['state'] == '申诉中', 'INVALID_TRANSITION', '申诉已处理或状态无效')
        winner = self.db.execute('SELECT * FROM claims WHERE id=?', (m['winner'],)).fetchone()
        decision = '冒领成立' if valid else '超时按不成立关闭' if timeout else '冒领不成立'
        self.db.execute('UPDATE appeals SET state=?,decision=? WHERE id=?', ('已支持' if valid else '已驳回', decision, appeal_id))
        if valid:
            self.db.execute("UPDATE matches SET state='已关闭' WHERE id=?", (m['id'],)); self.db.execute("UPDATE claims SET state='已关闭' WHERE id=?", (winner['id'],))
            self.touch(found['id'], '待匹配'); self.touch(m['lost'], '待匹配'); self.credit(winner['user_id'], 'false_claim', a['id'], actor['id'])
            self.notify(a['user_id'], '申诉成立，物品重新待匹配；已优先向您推送，请在候选列表重新申请')
            self.event(m['id'], actor['id'], '已关闭', decision + '；物品重新待匹配，优先推送申诉人')
            # Preserve the dispute trail. The next manual claim gets priority over ordinary queued claims.
            for row in list(self.db.execute("SELECT id,data FROM items WHERE owner=? AND kind='lost'", (a['user_id'],))):
                lost = self.item(row['id'])
                if lost['state'] not in ['已完成', '已关闭'] and score(lost['payload'], found['payload'], self.policy)['eligible']:
                    prior = self.db.execute('SELECT id FROM matches WHERE lost=? AND found=?', (lost['id'], found['id'])).fetchone()
                    if prior:
                        self.db.execute("UPDATE matches SET state='已匹配待确认',priority_user=?,deadline=?,winner=NULL WHERE id=?", (a['user_id'], self.now + self.policy['matchHours'] * 3600000, prior['id']))
                        self.event(prior['id'], actor['id'], '已匹配待确认', '申诉成立后的优先候选，可重新申请核验')
                    break
        else:
            self.db.execute("UPDATE matches SET state='已完成' WHERE id=?", (m['id'],)); self.touch(found['id'], '已完成'); self.touch(m['lost'], '已完成')
            if not timeout: self.credit(a['user_id'], 'malicious_appeal', a['id'], actor['id'])
            self.event(m['id'], actor['id'], '已完成', decision + '；维持原认领结果')
        self.notify(a['user_id'], decision); self.notify(winner['user_id'], decision)
        return {'decision': decision}

    def expire(self):
        for a in list(self.db.execute("SELECT id FROM appeals WHERE state='待裁定' AND deadline<?", (self.now,))):
            self.decide({'id': 'system', 'role': 'admin'}, a['id'], False, True)
        for m in list(self.db.execute("SELECT * FROM matches WHERE state IN ('已匹配待确认','认领申请中','凭证核验中','竞领中') AND deadline<?", (self.now,))):
            self.db.execute("UPDATE matches SET state='已关闭' WHERE id=?", (m['id'],))
            for c in list(self.db.execute("SELECT * FROM claims WHERE match_id=? AND state IN ('排队','核验中','已通过')", (m['id'],))):
                self.db.execute("UPDATE claims SET state='已关闭' WHERE id=?", (c['id'],)); self.credit(c['user_id'], 'no_show', m['id'], 'system')
            self.touch(m['lost'], '待匹配'); self.event(m['id'], 'system', '已关闭', '匹配超过处理时限自动关闭')
            other = self.db.execute("SELECT 1 FROM matches WHERE found=? AND state NOT IN ('已关闭','已完成')", (m['found'],)).fetchone()
            if other: self.advance(m['found'])
            else: self.touch(m['found'], '待匹配')

    def view_match(self, m, actor):
        lost, found = self.item(m['lost']), self.item(m['found'])
        privileged = actor['role'] == 'admin' or found['owner'] == actor['id']
        claims = []
        for row in self.db.execute('SELECT * FROM claims WHERE found=? ORDER BY created,id', (m['found'],)):
            own = row['user_id'] == actor['id']
            claims.append({'claimId': row['id'], 'userId': row['user_id'], 'name': self.user(row['user_id'])['name'],
                           'state': row['state'], 'score': row['score'], 'level': row['level'],
                           'answer': row['answer'] if privileged or own else '', 'evidenceText': row['evidence'] if privileged or own else '',
                           'evidenceImage': row['image'] if privileged or own else '', 'credit': self.user(row['user_id'])['credit']})
        events = [dict(e) for e in self.db.execute('SELECT * FROM events WHERE match_id=? ORDER BY seq', (m['id'],))]
        return {'matchId': m['id'], 'lostId': m['lost'], 'foundId': m['found'], 'foundOwner': found['owner'], 'lostOwner': lost['owner'],
                'state': m['state'], 'score': m['score'], 'category': found['payload']['category'], 'place': found['payload']['place'],
                'question': found['payload']['question'], 'deadline': m['deadline'], 'claims': claims, 'events': events}
