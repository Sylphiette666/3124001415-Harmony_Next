const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');
const {DatabaseSync}=require('node:sqlite');
// Node 22.13+ (or Node 24) supplies node:sqlite. No Web dependencies are required.
const {findTypeScript,readOptions}=require('./test-knowledge-support.cjs');
const ts=findTypeScript(readOptions());
global.Observed=target=>target;
const root=path.resolve(__dirname,'..');const db=new DatabaseSync(':memory:');
const native={executeSql:async(sql,params=[])=>{db.prepare(sql).run(...params);},querySql:async(sql,params=[])=>{
 const stmt=db.prepare(sql);stmt.setReturnArrays(true);const rows=stmt.all(...params);let index=-1;
 return {goToNextRow:()=>++index<rows.length,getString:i=>String(rows[index][i]),getLong:i=>Number(rows[index][i]),close:()=>{}};
},beginTransaction:()=>db.exec('BEGIN'),commit:()=>db.exec('COMMIT'),rollBack:()=>db.exec('ROLLBACK')};
const cache={};
function load(name){if(cache[name])return cache[name];const exports={};const filename=path.join(root,'entry/src/main/ets/model',name+'.ets');
 const code=ts.transpileModule(fs.readFileSync(filename,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 const requireLocal=id=>id==='@kit.ArkData'?{relationalStore:{getRdbStore:async()=>native,SecurityLevel:{S1:1}}}:id==='@kit.ArkTS'?{util:{TextDecoder:{create:()=>({decodeToString:bytes=>new TextDecoder().decode(bytes)})}}}:id.startsWith('.')?load(id.slice(2)):{};
 vm.runInThisContext(`(function(require,exports){${code}\n})`,{filename})(requireLocal,exports);return cache[name]=exports;
}
(async()=>{
 const K=load('Knowledge'),{CourseStore}=load('CourseStore');const store=new CourseStore();
 const seed=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/course-documents.json'));
 await assert.rejects(store.init({resourceManager:{getRawFileContent:async()=>{throw new Error('temporary resource failure');}}}),/temporary resource failure/);
 await store.init({resourceManager:{getRawFileContent:async()=>seed}});
 assert.equal((await store.documents()).length,12);
 let segments=await store.segments();
 assert.match(K.retrieve('如何通过 ArkAF 意图自动提问？',segments)[0].segment.title,/ArkAF/);
 assert.equal(K.retrieve('quantumfalconxyz',segments).length,0);
 assert.equal(K.cosine([1,0],[1,0]),1);assert.equal(K.cosine([1],[1,2]),0);assert.equal(K.cosine([NaN],[1]),0);
 const body='前文😀。'.repeat(200); const doc={id:'test',title:'唯一量子鲸鱼',source:'课堂',body,revision:1,updated:0};
 for(const s of K.splitDocument(doc)){assert.equal(s.text,body.slice(s.start,s.end));assert(!/^[\uDC00-\uDFFF]/.test(s.text));assert(!/[\uD800-\uDBFF]$/.test(s.text));}
 const points='字😀文';let i=0;const cuts=[];while(i<points.length){i=K.nextCodePoint(points,i);cuts.push(i);}assert.deepEqual(cuts,[1,3,4]);
 const question='怎样修改课程资料？';assert.equal(K.extractQuestion('courselearning://ask?question='+encodeURIComponent(question)),question);
 assert.equal(K.extractQuestion('courselearning://ask-evil?question=x'),'');assert.equal(K.extractQuestion('courselearning://ask?question=%zz'),'');assert.equal(K.extractQuestion('',question),question);
 await store.save({...doc,body:'量子鲸鱼的标记是青色。该资料用于验证新增后立即可检索。'});
 const old=(await store.segments()).filter(s=>s.documentId==='test');assert.equal(old.length,1);
 assert.match(K.localAnswer('量子鲸鱼',K.retrieve('量子鲸鱼',await store.segments())),/青色/);
 await store.save({...doc,body:'量子鲸鱼的标记是橙色。该资料用于验证修改后不会再引用旧颜色。'});
 assert.match(K.localAnswer('量子鲸鱼',K.retrieve('量子鲸鱼',await store.segments())),/橙色/);
 assert(!(await store.segments()).some(s=>s.text.includes('青色')));
 await store.vectors(old,[[1,0]],'old-model');assert(!(await store.segments()).some(s=>s.model==='old-model'));
 await assert.rejects(store.save({...doc,title:'',body:'x'}));assert.match((await store.documents()).find(d=>d.id==='test').body,/橙色/);
 await store.remove('test');assert.equal(K.retrieve('量子鲸鱼',await store.segments()).length,0);
 await store.vectors(old,[[1,0]],'old-model');assert(!(await store.segments()).some(s=>s.documentId==='test'));
 await store.saveSettings({endpoint:'https://example.invalid',cloud:true}); assert.deepEqual(await store.settings(),{endpoint:'https://example.invalid',cloud:true});
 const sem={...segments[0],id:'semantic',text:'不同表达',title:'同义资料',vector:[1,0],model:'m'};
 assert(K.retrieve('noexact', [sem], [1,0], 'm').length===1);assert.equal(K.retrieve('noexact',[sem],[1,0],'different').length,0);
 await Promise.all([store.save({...doc,body:'并发资料保存测试，事务串行执行以避免数据库状态互相覆盖。'}),store.remove('test')]);
 assert(!(await store.documents()).some(d=>d.id==='test'));db.close();
 assert.notEqual(new K.ChatMessage('a',false,1).id,new K.ChatMessage('b',false,1).id);
 console.log('PASS: initialization retry; 12 seeds; split offsets/Unicode; retrieval/RRF; Want parsing; SQLite CRUD/rollback/stale vectors/concurrency.');
})().catch(e=>{console.error(e);process.exitCode=1;});
