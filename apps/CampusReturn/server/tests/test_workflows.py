import base64
from concurrent.futures import ThreadPoolExecutor
import copy
import io
import json
import time

from fastapi.testclient import TestClient
import jwt
from PIL import Image
import pytest

from server.app import create_app
from server.database import connect
from server.engine import DEFAULT, DAY, credential_hash, score

KEY = 'private-signing-key-for-this-test-only-not-a-real-credential'
SECRET = 'Private-Case-Sensitive_Test_Account-42'
NOW = 1793232000000
buffer = io.BytesIO(); Image.new('RGB', (80, 50), 'blue').save(buffer, 'JPEG')
PHOTO = base64.b64encode(buffer.getvalue()).decode()


@pytest.fixture
def env(tmp_path):
    path = tmp_path / 'test.db'; clock = [NOW]
    with connect(path) as db:
        for id, role, credit in [('alice','user',100),('bob','user',100),('charlie','user',110),('david','user',100),('admin','admin',100)]:
            db.execute('INSERT INTO users(id,name,role,secret,credit) VALUES (?,?,?,?,?)', (id,id,role,credential_hash(SECRET,KEY),credit))
    return TestClient(create_app(path, KEY, lambda:clock[0])), path, clock


def auth(c, user='alice'):
    r=c.post('/v1/auth/token',json={'deviceId':user,'deviceKey':SECRET});assert r.status_code==200
    return {'Authorization':'Bearer '+r.json()['accessToken']}


def item(id='lost-alice-001',kind='lost',**changes):
    return {'itemId':id,'kind':kind,'category':'校园卡','color':'蓝色','place':'图书馆', 'occurredAt':NOW-(3600000 if kind=='found' else 7200000),
            'description':'蓝色校园卡 图书馆 张同学 202600001','ocrText':'校园卡 张同学 202600001', 'imageBase64':PHOTO,
            'question':'编号是什么' if kind=='found' else '', 'answer':'202600001' if kind=='found' else '',**changes}


def post(c,path,data=None,user='alice'):
    return c.post(path,json=data,headers=auth(c,user))


def seed(c, second=True):
    for u,v in [('alice',item()),('bob',item('found-bob-001','found'))]+([('charlie',item('lost-charlie-001'))] if second else []):
        assert post(c,'/v1/items',v,u).status_code==200
    return c.get('/v1/matches',headers=auth(c)).json()['matches'][0]['matchId']


def claim(c,user='alice',found='found-bob-001'):
    lost='lost-alice-001' if user=='alice' else 'lost-'+user+'-001'
    r=post(c,'/v1/claims',{'lostId':lost,'foundId':found},user);assert r.status_code==200,r.text
    return r.json()['claimId']


def answer(c,id,user='alice',**extra):
    return post(c,f'/v1/claims/{id}/answer',{'answer':'202600001',**extra},user)


def completed(c):
    m=seed(c);id=claim(c);assert answer(c,id).status_code==200
    r=post(c,f'/v1/matches/{m}/complete',user='bob');assert r.status_code==200,r.text
    return m


def test_auth_roles_and_expired_forged_token(env):
    c,_,_=env
    assert c.get('/v1/me').status_code==401
    assert c.get('/v1/admin',headers=auth(c)).status_code==403
    assert c.get('/v1/admin',headers=auth(c,'admin')).status_code==200
    assert post(c,'/v1/admin/violations',{'userId':'bob','kind':'false_post','reasonId':'reason-0001'}).status_code==403
    assert c.post('/v1/auth/token',json={'deviceId':'alice','deviceKey':SECRET.lower()}).status_code==401
    assert c.post('/v1/auth/token',json={'deviceId':'alice','deviceKey':SECRET,'role':'admin'}).status_code==422
    for key, expiry in [(KEY,int(time.time())-1),('forged-key',int(time.time())+600)]:
        token=jwt.encode({'sub':'alice','role':'admin','iat':int(time.time())-10,'exp':expiry,'aud':'campus-return','iss':'campus-return'},key,algorithm='HS256')
        assert c.get('/v1/admin',headers={'Authorization':'Bearer '+token}).status_code==401


def test_idempotence_conflict_atomic_parallel_and_private_clues(env):
    c,path,_=env;p=item('found-bob-001','found')
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses=list(pool.map(lambda _:post(c,'/v1/items',p,'bob'),range(6)))
    assert all(r.status_code==200 for r in responses)
    assert sum(r.json()['status']=='created' for r in responses)==1
    assert post(c,'/v1/items',{**p,'color':'红色'},'bob').status_code==409
    assert post(c,'/v1/items',p,'alice').status_code==409
    public=c.get('/v1/items',headers=auth(c)).json()['items'][0];assert not public['ocrText'] and not public['imageBase64']
    assert 'answer' not in public and public['imagePrivate']
    assert '202600001' not in public['description']
    own=c.get('/v1/items?mine=true',headers=auth(c,'bob')).json()['items'][0];assert '202600001' in own['ocrText']
    assert post(c,'/v1/items',{**item('invalid-0001'),'imageBase64':'not-base64'}).status_code==422


def test_one_lost_item_cannot_complete_twice_across_found_posts(env):
    c,_,_=env
    m=seed(c,False)
    assert post(c,'/v1/items',item('found-bob-002','found'),'bob').status_code==200
    first=claim(c); second=claim(c,found='found-bob-002')
    assert answer(c,first).status_code==200
    assert answer(c,second,level=2,evidenceText='编号202600001').status_code==200
    assert post(c,f'/v1/claims/{second}/review',{'passed':True,'score':0},'bob').status_code==409
    assert post(c,f'/v1/claims/{second}/review',{'passed':True,'score':90},'bob').status_code==200
    assert post(c,f'/v1/matches/{m}/complete',user='bob').status_code==200
    rows=c.get('/v1/matches',headers=auth(c)).json()['matches']
    other=next(r for r in rows if r['foundId']=='found-bob-002')
    assert other['state']=='已关闭'
    assert post(c,f'/v1/matches/{other["matchId"]}/complete',user='bob').status_code==409
    assert c.get('/v1/me',headers=auth(c)).json()['credit']==105


def test_scoring_hard_gates_nearby_window_jaccard_and_weights():
    lost=item();found=item('found-bob-001','found')
    result=score(lost,found,DEFAULT);assert result['eligible'] and result['score']>.9
    assert not score(lost,{**found,'category':'手机'},DEFAULT)['eligible']
    assert not score(lost,{**found,'occurredAt':lost['occurredAt']-1},DEFAULT)['eligible']
    assert not score(lost,{**found,'occurredAt':lost['occurredAt']+8*DAY},DEFAULT)['eligible']
    candidate={**found,'place':'图书馆北门','ocrText':'另一人 12345678','description':'不同的东西'}
    a=copy.deepcopy(DEFAULT);a['weights']={'place':.8,'time':.1,'ocr':.05,'text':.04,'color':.01}
    b=copy.deepcopy(DEFAULT);b['weights']={'place':.05,'time':.1,'ocr':.7,'text':.1,'color':.05}
    assert score(lost,candidate,a)['score']>score(lost,candidate,b)['score']+.4


def test_candidate_low_score_manual_claim_and_policy_permissions(env):
    c,_,_=env
    assert post(c,'/v1/items',item()).status_code==200
    assert post(c,'/v1/items',item('found-bob-001','found',place='操场',ocrText='其它编号 00000999',description='找到卡片',color='白色'),'bob').status_code==200
    data=c.get('/v1/candidates/lost-alice-001',headers=auth(c)).json();assert len(data['candidates'])==1 and not data['candidates'][0]['automatic']
    assert claim(c)
    assert c.get('/v1/candidates/lost-alice-001',headers=auth(c,'charlie')).status_code==403
    p=copy.deepcopy(DEFAULT);p['weights']['place']=.9
    assert post(c,'/v1/admin/policy',p,'admin').status_code==422
    p=copy.deepcopy(DEFAULT);p['threshold']=.1
    assert post(c,'/v1/admin/policy',p).status_code==403
    assert post(c,'/v1/admin/policy',p,'admin').status_code==200


def test_proof_required_and_only_publisher_completes(env):
    c,_,_=env;m=seed(c,False)
    assert post(c,f'/v1/matches/{m}/complete',user='bob').json()['error']['code']=='PROOF_REQUIRED'
    assert post(c,f'/v1/matches/{m}/complete').status_code==403
    id=claim(c)
    assert post(c,f'/v1/matches/{m}/complete',user='bob').json()['error']['code']=='QUEUE_NOT_FINISHED'
    assert answer(c,id,'charlie').status_code==403
    assert answer(c,id).status_code==200
    assert post(c,f'/v1/matches/{m}/complete',user='bob').status_code==200
    assert post(c,f'/v1/matches/{m}/complete',user='bob').status_code==409
    assert c.get('/v1/me',headers=auth(c)).json()['credit']==105


def test_competition_serial_failure_release_ranking_and_notifications(env):
    c,path,_=env;m=seed(c);a=claim(c);b=claim(c,'charlie')
    assert answer(c,b,'charlie').status_code==409
    with connect(path) as db: assert db.execute("SELECT COUNT(*) FROM claims WHERE state='核验中'").fetchone()[0]==1
    assert answer(c,a).status_code==200
    assert post(c,f'/v1/matches/{m}/complete',user='bob').status_code==409
    assert answer(c,b,'charlie').status_code==200
    result=post(c,f'/v1/matches/{m}/complete',user='bob');assert result.status_code==200 and result.json()['winner']=='charlie'
    messages=c.get('/v1/notifications',headers=auth(c)).json()['notifications'];assert any('自动拒绝' in n['message'] for n in messages)
    assert c.get('/v1/me',headers=auth(c)).json()['credit']==100


def test_failed_answer_releases_next_without_client_level_upgrade(env):
    c,path,_=env;seed(c);a=claim(c);b=claim(c,'charlie')
    assert answer(c,a,answer='错误').json()['state']=='已关闭'
    with connect(path) as db: assert db.execute('SELECT state FROM claims WHERE id=?',(b,)).fetchone()[0]=='核验中'
    r=answer(c,b,'charlie',level=3,evidenceText='202600001',evidenceImage=PHOTO);assert r.status_code==200 and r.json()['state']=='核验中'
    assert post(c,f'/v1/claims/{b}/review',{'passed':True,'score':95},'alice').status_code==403
    assert post(c,f'/v1/claims/{b}/review',{'passed':True,'score':95},'bob').status_code==200


def test_claims_submitted_concurrently_still_only_one_verifier(env):
    c,path,_=env;seed(c)
    with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(lambda u:claim(c,u),['alice','charlie']))
    with connect(path) as db:
        states=[r[0] for r in db.execute('SELECT state FROM claims')];assert sorted(states)==['排队','核验中']
        assert db.execute("SELECT COUNT(*) FROM matches WHERE state='竞领中'").fetchone()[0]==2


def test_appeal_evidence_hierarchy_state_guard_and_true_decision(env):
    c,path,_=env;m=completed(c)
    weak={'lostId':'lost-charlie-001','level':1,'evidenceText':'答题记录'}
    assert post(c,f'/v1/matches/{m}/appeals',weak,'charlie').json()['error']['code']=='EVIDENCE_TOO_WEAK'
    assert post(c,f'/v1/matches/{m}/appeals',{**weak,'level':3,'evidenceText':'202600001'},'charlie').json()['error']['code']=='EVIDENCE_IMAGE_REQUIRED'
    strong={**weak,'level':3,'evidenceText':'本人证件OCR编号202600001','evidenceImage':PHOTO}
    r=post(c,f'/v1/matches/{m}/appeals',strong,'charlie');assert r.status_code==200,r.text
    assert post(c,f'/v1/matches/{m}/complete',user='bob').json()['error']['code']=='INVALID_TRANSITION'
    id=r.json()['appealId'];assert post(c,f'/v1/appeals/{id}/decision',{'valid':True},'alice').status_code==403
    assert post(c,f'/v1/appeals/{id}/decision',{'valid':True},'admin').status_code==200
    assert post(c,f'/v1/appeals/{id}/decision',{'valid':True},'admin').status_code==409
    assert c.get('/v1/me',headers=auth(c)).json()['credit']==65
    assert c.get('/v1/me',headers=auth(c)).json()['false_claims']==1
    found=next(r for r in c.get('/v1/items',headers=auth(c,'bob')).json()['items'] if r['kind']=='found');assert found['state']=='待匹配'
    assert claim(c,'charlie')


def test_false_appeal_credit_and_timeout_no_unjust_penalty(env):
    c,_,clock=env;m=completed(c);data={'lostId':'lost-charlie-001','level':2,'evidenceText':'编号202600001'}
    id=post(c,f'/v1/matches/{m}/appeals',data,'charlie').json()['appealId']
    assert post(c,f'/v1/appeals/{id}/decision',{'valid':False},'bob').status_code==200
    assert c.get('/v1/me',headers=auth(c,'charlie')).json()['credit']==90
    id=post(c,f'/v1/matches/{m}/appeals',data,'charlie').json()['appealId'];clock[0]+=3*DAY
    r=c.get('/v1/appeals',headers=auth(c,'charlie'));assert any(a['decision']=='超时按不成立关闭' for a in r.json()['appeals'])
    assert c.get('/v1/me',headers=auth(c,'charlie')).json()['credit']==90


def test_credit_publish_floor_ban_and_idempotent_penalty(env):
    c,path,_=env
    for i in range(3):assert post(c,'/v1/admin/violations',{'userId':'alice','kind':'false_post','reasonId':f'reason-000{i}'},'admin').status_code==200
    assert c.get('/v1/me',headers=auth(c)).json()['credit']==55
    assert post(c,'/v1/admin/violations',{'userId':'alice','kind':'false_post','reasonId':'reason-0000'},'admin').json()['credit']==55
    assert post(c,'/v1/items',item()).status_code==403
    with connect(path) as db:db.execute("UPDATE users SET false_claims=2 WHERE id='charlie'")
    assert post(c,'/v1/items',item('lost-charlie-001'),'charlie').status_code==200
    assert post(c,'/v1/items',item('found-bob-001','found'),'bob').status_code==200
    assert post(c,'/v1/claims',{'lostId':'lost-charlie-001','foundId':'found-bob-001'},'charlie').json()['error']['code']=='CLAIM_BANNED'
    assert c.get('/v1/admin',headers=auth(c,'admin')).json()['users']


def test_incremental_sync_no_skips_and_item_version_changes(env):
    c,_,_=env;seed(c)
    cursor=0;seen=set()
    for _ in range(20):
        r=c.get(f'/v1/sync?cursor={cursor}&limit=1',headers=auth(c)).json();cursor=r['cursor'];seen.update(i['itemId'] for i in r['items'])
        if not r['hasMore']:break
    assert seen=={'lost-alice-001','found-bob-001','lost-charlie-001'}
    assert not c.get(f'/v1/sync?cursor={cursor}',headers=auth(c)).json()['items']
    claim(c)
    r=c.get(f'/v1/sync?cursor={cursor}',headers=auth(c)).json();assert r['items'] and any(i['state']=='凭证核验中' for i in r['items'])


def test_match_timeout_timeline_and_reject_higher_replacement(env):
    c,_,clock=env;m=seed(c,False)
    assert post(c,'/v1/items',item('lost-charlie-001',place='图书馆正门',occurredAt=NOW-3600001),'charlie').status_code==200
    r=post(c,'/v1/matches',{'lostId':'lost-charlie-001','foundId':'found-bob-001'},'charlie');assert r.status_code==409 and r.json()['error']['code']=='MATCH_LOCKED'
    clock[0]+=3*DAY
    r=c.get('/v1/matches',headers=auth(c)).json()['matches'];assert r[0]['state']=='已关闭'
    assert any('超' in e['message'] for e in r[0]['events'])


def test_statistics_and_no_error_secret_echo(env):
    c,_,_=env;seed(c)
    r=c.get('/v1/admin',headers=auth(c,'admin')).json();assert r['stats']['items']==3 and r['categories']==[{'name':'校园卡','count':3}]
    bad=c.post('/v1/auth/token',json={'deviceId':'bad','deviceKey':SECRET,'role':'admin'});assert SECRET not in bad.text
    assert c.post('/v1/items',content=b'x'*16000001).status_code==413
