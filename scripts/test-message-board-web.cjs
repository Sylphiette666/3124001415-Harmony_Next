#!/usr/bin/env node
'use strict';
// Real HTML/CSS/JS in an isolated browser; native transport is mocked here.
// Requires Node >=20 and Playwright. Set NODE_PATH to the installed packages path if needed.
const assert=require('node:assert/strict'), path=require('node:path'), fs=require('node:fs');
const {pathToFileURL}=require('node:url');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
  const options={headless:true};
  if(process.argv.includes('--edge')) options.channel='msedge';
  const browser=await chromium.launch(options); let passed=0;
  try {
    const page=await browser.newPage({viewport:{width:377,height:760},deviceScaleFactor:1});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{
      window.calls=[];
      window.NativeBoard=Object.fromEntries(['submitMessage','requestHistory','deleteMessage','showToast'].map(name=>[name,value=>{
        window.calls.push({name,value});return JSON.stringify({ok:true});
      }]));
    });
    await page.goto(pathToFileURL(path.join(root,'entry/src/main/resources/rawfile/message-board.html')).href);
    let sequence=0;
    const send=async(kind,messages=[],extra={})=>page.evaluate(event=>window.MessageBoard.receive(event),{kind,messages,sequence:++sequence,...extra});
    const check=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
    await check('initial page waits for native history',async()=>assert.equal(await page.locator('#submitMessage').isDisabled(),true));
    await send('snapshot');
    await check('native snapshot enables form and renders empty state',async()=>{
      assert.equal(await page.locator('#submitMessage').isEnabled(),true);assert.equal(await page.locator('#empty').isVisible(),true);
    });
    await check('empty input is rejected without invoking the bridge',async()=>{
      await page.locator('#submitMessage').click();assert.ok((await page.locator('#feedback').innerText()).includes('称呼'));
      assert.equal((await page.evaluate(()=>window.calls)).length,0);
    });
    const text='<img src=x onerror="window.hacked=1">\n中文🙂 "引号" \\ 路径';
    await page.locator('#author').fill('测试同学');await page.locator('#body').fill(text);await page.locator('#submitMessage').click();
    const submitted=await page.evaluate(()=>JSON.parse(window.calls.find(c=>c.name==='submitMessage').value));
    const message={...submitted,createdAt:1791417600000};
    await check('form sends complete JSON and blocks duplicate clicks while saving',async()=>{
      assert.equal(submitted.body,text);assert.equal(submitted.author,'测试同学');assert.equal(await page.locator('#submitMessage').isDisabled(),true);
    });
    await send('saved',[message],{requestId:submitted.id,message:'留言已保存到本机'});
    await check('save acknowledgement clears body and synchronizes title',async()=>{
      assert.equal(await page.locator('#body').inputValue(),'');assert.equal(await page.title(),'网页留言板 · 1 条');
      assert.equal(await page.locator('#submitMessage').isEnabled(),true);
    });
    await check('untrusted markup renders as literal text without running scripts',async()=>{
      assert.equal(await page.locator('.body').innerText(),text);assert.equal(await page.locator('.body img').count(),0);
      assert.equal(await page.evaluate(()=>window.hacked),undefined);
    });
    await check('search filters locally and recovers the list',async()=>{
      await page.locator('#search').fill('不存在的词');assert.equal(await page.locator('.message').count(),0);
      await page.locator('#search').fill('中文');assert.equal(await page.locator('.message').count(),1);
      await page.locator('#search').fill('');
    });
    await check('native notification displays and can be dismissed',async()=>{
      await send('notice',[],{message:'来自原生的测试通知'});assert.equal(await page.locator('#noticeText').innerText(),'来自原生的测试通知');
      await page.locator('#dismissNotice').click();assert.equal(await page.locator('#notice').isVisible(),false);
    });
    await check('webpage invokes native toast',async()=>{
      await page.locator('#toastButton').click();assert.equal(await page.evaluate(()=>window.calls.at(-1).name),'showToast');
    });
    await check('delete cancellation preserves data and confirmation invokes native deletion',async()=>{
      await page.locator('.delete').click();await page.locator('#cancelDelete').click();assert.equal(await page.locator('.message').count(),1);
      await page.locator('.delete').click();await page.locator('#confirmDelete').click();
      assert.equal(await page.evaluate(()=>window.calls.at(-1).value),message.id);
      await send('deleted',[],{requestId:message.id,message:'留言已删除'});assert.equal(await page.locator('.message').count(),0);
    });
    await check('save failure preserves draft and offers history retry',async()=>{
      await page.locator('#body').fill('保存失败后保留的草稿');await page.locator('#submitMessage').click();
      const request=await page.evaluate(()=>JSON.parse(window.calls.filter(c=>c.name==='submitMessage').at(-1).value));
      await send('error',[],{requestId:request.id,message:'保存失败，请重试'});
      assert.equal(await page.locator('#body').inputValue(),'保存失败后保留的草稿');assert.equal(await page.locator('#retryHistory').isVisible(),true);
      await page.locator('#retryHistory').click();assert.equal(await page.evaluate(()=>window.calls.at(-1).name),'requestHistory');
    });
    await check('late history event cannot overwrite newer state',async()=>{
      await send('snapshot',[message]);
      await page.evaluate(()=>window.MessageBoard.receive({kind:'snapshot',messages:[],sequence:1}));
      assert.equal(await page.locator('.message').count(),1);
    });
    await check('long text fits phone and tablet viewports',async()=>{
      await send('snapshot',[{...message,body:'很长的内容'.repeat(100)}]);
      for(const width of [320,377,800]){await page.setViewportSize({width,height:800});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);}
    });
    const out=path.join(root,'.test','board-browser');fs.mkdirSync(out,{recursive:true});
    await page.setViewportSize({width:377,height:800});await send('snapshot',[{...message,body:'记录今天的学习：网页与原生之间可以互相传递消息。'}]);
    await page.screenshot({path:path.join(out,'message-board.png'),fullPage:true});
    await check('native persistence is not replaced by browser localStorage or network',async()=>{
      assert.equal(await page.evaluate(()=>localStorage.length),0);assert.deepEqual(errors,[]);
    });
    console.log(`Message board browser: ${passed}/14 passed`);
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
