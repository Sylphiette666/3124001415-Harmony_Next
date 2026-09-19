#!/usr/bin/env node
'use strict';
// Runs production ETS model/controller/HTTP/store code with isolated platform adapters.
// Pass --live to additionally query Open-Meteo over HTTPS (no API key).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const https = require('node:https');
const root = path.resolve(__dirname, '..');
const homeIndex = process.argv.indexOf('--deveco-home');
const home = homeIndex >= 0 ? process.argv[homeIndex + 1] : process.env.DEVECO_HOME;
if (!home) throw new Error('Pass --deveco-home DIR or set DEVECO_HOME.');
const ts = require(path.join(home, 'tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js'));
const requests = [];
let offline = false;
let probeError = false;
let handler = async () => ({ responseCode: 200, result: fixture() });
const prefValues = new Map();
let failStorage = false;
const prefs = {
  getSync(key, fallback) { if (failStorage) throw new Error('disk'); return prefValues.get(key) ?? fallback; },
  putSync(key, value) { if (failStorage) throw new Error('disk'); prefValues.set(key, value); },
  async flush() { if (failStorage) throw new Error('disk'); }
};
const platform = {
  '@kit.NetworkKit': {
    connection: { hasDefaultNetSync() { if (probeError) throw new Error('probe'); return !offline; } },
    http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 },
      createHttp() {
        const request = { destroyed: 0, url: '', options: null,
          request(url, options) { this.url = url; this.options = options; return handler(this); },
          destroy() { this.destroyed++; }
        };
        requests.push(request); return request;
      }
    }
  },
  '@kit.ArkData': { preferences: { getPreferencesSync(context, options) {
    assert.equal(options.name, 'course_weather_v1'); return prefs;
  } } }
};
const modules = new Map();
function load(file) {
  const full = path.resolve(root, file);
  if (modules.has(full)) return modules.get(full).exports;
  const compiled = ts.transpileModule(fs.readFileSync(full, 'utf8'), {
    fileName: full.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  });
  const module = { exports: {} }; modules.set(full, module);
  const requireFn = name => {
    if (platform[name]) return platform[name];
    if (name.startsWith('.')) return load(path.resolve(path.dirname(full), name + '.ets'));
    throw new Error('Unexpected import ' + name);
  };
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, require: requireFn, Date, console,
    setTimeout, clearTimeout }, { filename: full });
  return module.exports;
}
const data = load('entry/src/main/ets/model/WeatherData.ets');
const catalog = load('entry/src/main/ets/model/WeatherCities.ets');
const httpModule = load('entry/src/main/ets/services/WeatherHttpClient.ets');
const { WeatherController } = load('entry/src/main/ets/model/WeatherController.ets');
const { WeatherStore } = load('entry/src/main/ets/model/WeatherStore.ets');
const guangzhou = catalog.findWeatherCity('');
const beijing = catalog.WEATHER_CITIES.find(c => c.name === '北京市');
function fixture(change = () => {}) {
  const dto = { utc_offset_seconds: 28800,
    current: { time: '2026-09-19T15:00', temperature_2m: 27.6, relative_humidity_2m: 62,
      apparent_temperature: 29, weather_code: 61, wind_speed_10m: 3.4, wind_direction_10m: 90, is_day: 1 },
    daily: { time: ['2026-09-19', '2026-09-20', '2026-09-21', '2026-09-22', '2026-09-23', '2026-09-24', '2026-09-25'],
      weather_code: [61, 0, 2, 3, 45, 95, 71], temperature_2m_max: [30, 31, 32, 30, 29, 28, 27],
      temperature_2m_min: [20, 21, 22, 21, 20, 19, 18], precipitation_probability_max: [80, 0, 5, 10, 20, 90, 95],
      wind_speed_10m_max: [1, 2, 3, 4, 5, 6, 7] }
  }; change(dto); return JSON.stringify(dto);
}
function deferred() { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; }
const tick = () => new Promise(resolve => setImmediate(resolve));
function memory() {
  return { cache: new Map(), selected: '', fail: false,
    read(id) { if (this.fail) throw new Error('disk'); return this.cache.get(id); },
    async write(entry) { if (this.fail) throw new Error('disk'); this.cache.set(entry.cityId, entry); },
    lastCity() { return this.selected; },
    async select(id) { if (this.fail) throw new Error('disk'); this.selected = id; }
  };
}
function setup(source = { async fetch() { return fixture(); }, cancel() {} }, storage = memory()) {
  const states = [];
  return { source, storage, states, controller: new WeatherController(source, storage, s => states.push(s)),
    last() { return states.at(-1); } };
}
const tests = [];
function test(name, run) { tests.push({ name, run }); }
test('catalog includes all 34 provinces with unique valid coordinates', () => {
  assert.equal(catalog.WEATHER_PROVINCES.length, 34); assert.equal(catalog.WEATHER_CITIES.length, 392);
  assert.equal(new Set(catalog.WEATHER_CITIES.map(c => c.id)).size, 392);
  for (const c of catalog.WEATHER_CITIES) {
    assert.ok(c.latitude >= 3 && c.latitude <= 54 && c.longitude >= 73 && c.longitude <= 136, c.name);
    assert.ok(catalog.citiesInProvince(c.province).some(item => item.id === c.id));
  }
  assert.equal(guangzhou.name, '广州市'); assert.ok(beijing);
});
test('province linkage includes Guangdong cities and special regions', () => {
  assert.equal(catalog.citiesInProvince('广东省').length, 21);
  for (const p of ['北京市', '香港特别行政区', '澳门特别行政区', '台湾省']) assert.ok(catalog.citiesInProvince(p).length);
  assert.equal(catalog.findWeatherCity('invalid').name, '广州市');
});
test('parses current conditions and seven forecasts', () => {
  const r = data.parseWeather(fixture(), guangzhou, 123);
  assert.equal(r.temperature, '28°'); assert.equal(r.condition, '小雨'); assert.equal(r.humidity, '62%');
  assert.equal(r.wind, '3级'); assert.equal(r.direction, '东风'); assert.equal(r.days.length, 7);
  assert.equal(r.days[0].rain, '80%'); assert.equal(r.cityId, guangzhou.id); assert.equal(r.fetchedAt, 123);
});
test('missing optional numbers stay missing instead of becoming zero', () => {
  const r = data.parseWeather(fixture(d => { d.current.relative_humidity_2m=null; d.current.wind_speed_10m=null;
    d.current.apparent_temperature=null; d.daily.precipitation_probability_max[0]=null; d.daily.temperature_2m_min[0]=null; }), guangzhou);
  assert.equal(r.humidity, '—'); assert.equal(r.wind, '—'); assert.equal(r.feelsLike, '—');
  assert.equal(r.days[0].rain, '—'); assert.equal(r.days[0].low, '—');
});
test('zero humidity, precipitation and subzero temperatures remain valid', () => {
  const r = data.parseWeather(fixture(d => { d.current.temperature_2m=-7.6; d.current.relative_humidity_2m=0; }), guangzhou);
  assert.equal(r.temperature, '-8°'); assert.equal(r.humidity, '0%'); assert.equal(r.days[1].rain, '0%');
});
test('rejects malformed JSON, missing current temperature and service errors', () => {
  for (const raw of ['{', 'null', '{}', '{"error":true}', fixture(d => { d.current.temperature_2m=null; })])
    assert.throws(() => data.parseWeather(raw, guangzhou), e => e.kind === 'data');
});
test('rejects mismatched arrays, invalid dates and wrong time zones', () => {
  const changes = [d => { d.daily.weather_code.pop(); }, d => { d.daily.time[0]='bad'; },
    d => { d.daily.time[2]=d.daily.time[1]; }, d => { d.utc_offset_seconds=0; }, d => { d.current.time='bad'; }];
  for (const change of changes) assert.throws(() => data.parseWeather(fixture(change), guangzhou));
});
test('known weather codes and unknown codes are safe', () => {
  assert.equal(data.weatherLabel(0, false).icon, 'moon'); assert.equal(data.weatherLabel(48).icon, 'fog');
  assert.equal(data.weatherLabel(73).label, '中雪'); assert.equal(data.weatherLabel(96).icon, 'storm');
  assert.equal(data.weatherLabel(999).label, '天气状况暂无'); assert.equal(data.weatherLabel(null).label, '天气状况暂无');
});
test('Beaufort thresholds and circular wind directions', () => {
  for (const [speed, level] of [[0,'0级'],[0.3,'1级'],[1.6,'2级'],[3.4,'3级'],[32.7,'12级及以上']])
    assert.equal(data.windLevel(speed), level);
  assert.equal(data.windLevel(null), '—'); assert.equal(data.windLevel(-1), '—');
  assert.equal(data.windDirection(360),'北风'); assert.equal(data.windDirection(225),'西南风');
});
test('dates use Beijing calendar even across UTC midnight', () => {
  const now=Date.parse('2026-09-19T16:30:00Z');
  assert.equal(data.forecastDateLabel('2026-09-20',now),'今天');
  assert.equal(data.forecastDateLabel('2026-09-21',now),'明天');
  assert.equal(data.forecastDateLabel('2026-09-22',now),'周二');
});
test('request uses HTTPS, fixed units, city coordinates and finite timeouts', async () => {
  const client=new httpModule.WeatherHttpClient(); await client.fetch(guangzhou);
  const r=requests.at(-1); const url=new URL(r.url);
  assert.equal(url.protocol,'https:'); assert.equal(url.searchParams.get('wind_speed_unit'),'ms');
  assert.equal(url.searchParams.get('timezone'),'Asia/Shanghai'); assert.equal(url.searchParams.get('forecast_days'),'7');
  assert.equal(url.searchParams.get('latitude'),String(guangzhou.latitude));
  assert.equal(r.options.usingCache,false); assert.equal(r.options.connectTimeout,6000); assert.equal(r.destroyed,1);
});
test('offline fails before creating HTTP request', async () => {
  offline=true; const count=requests.length;
  await assert.rejects(new httpModule.WeatherHttpClient().fetch(guangzhou), e => e.kind==='offline');
  assert.equal(requests.length,count); offline=false;
});
test('network probe failures still allow a successful HTTP query', async () => {
  probeError=true; await new httpModule.WeatherHttpClient().fetch(guangzhou); probeError=false;
});
test('HTTP 429 and 503 are friendly errors and release resources', async () => {
  for (const status of [429,503]) {
    handler=async () => ({responseCode:status,result:'{}'});
    await assert.rejects(new httpModule.WeatherHttpClient().fetch(guangzhou),e => e.kind==='server');
    assert.equal(requests.at(-1).destroyed,1);
  }
});
test('timeout and DNS failures are distinguishable and release resources', async () => {
  for (const [code,kind] of [[2300028,'timeout'],[2300006,'network']]) {
    handler=async () => { throw {code}; };
    await assert.rejects(new httpModule.WeatherHttpClient().fetch(guangzhou),e => e.kind===kind);
    assert.equal(requests.at(-1).destroyed,1);
  }
});
test('network loss during an HTTP request reports offline', async () => {
  handler=async () => { offline=true; throw {code:2300006}; };
  await assert.rejects(new httpModule.WeatherHttpClient().fetch(guangzhou),e => e.kind==='offline'); offline=false;
});
test('non-string HTTP body is rejected', async () => {
  handler=async () => ({responseCode:200,result:{}});
  await assert.rejects(new httpModule.WeatherHttpClient().fetch(guangzhou),e => e.kind==='data');
});
test('cancelled old request cannot destroy replacement HTTP request', async () => {
  const first=deferred(), second=deferred(); let count=0;
  handler=() => (++count===1 ? first.promise : second.promise);
  const client=new httpModule.WeatherHttpClient(); const a=client.fetch(guangzhou);
  const old=requests.at(-1); const b=client.fetch(beijing); const fresh=requests.at(-1);
  assert.equal(old.destroyed,1); first.resolve({responseCode:200,result:fixture()});
  await assert.rejects(a,e => e.kind==='cancelled'); assert.equal(fresh.destroyed,0);
  second.resolve({responseCode:200,result:fixture()}); await b; assert.equal(fresh.destroyed,1);
});
test('controller transitions loading to success and persists city and cache', async () => {
  const s=setup(); await s.controller.load(guangzhou);
  assert.deepEqual(s.states.map(v => v.status),['loading','success']); assert.equal(s.last().cached,false);
  assert.equal(s.storage.selected,guangzhou.id); assert.ok(s.storage.cache.has(guangzhou.id));
});
test('cached weather is labelled during refresh and remains labelled offline', async () => {
  const store=memory(); store.cache.set(guangzhou.id,{cityId:guangzhou.id,raw:fixture(),savedAt:Date.now()-1000});
  const s=setup({ async fetch(){throw new data.WeatherFailure('offline','无网络');},cancel(){} },store);
  await s.controller.load(guangzhou); assert.equal(s.states[0].cached,true); assert.equal(s.last().cached,true);
  assert.equal(s.last().status,'offline'); assert.equal(s.last().report.cityId,guangzhou.id);
});
test('expired, future-dated and wrong-city caches never display', async () => {
  for (const entry of [
    {cityId:guangzhou.id,raw:fixture(),savedAt:Date.now()-86401000},
    {cityId:guangzhou.id,raw:fixture(),savedAt:Date.now()+60000},
    {cityId:beijing.id,raw:fixture(),savedAt:Date.now()}]) {
    const store=memory(); store.cache.set(guangzhou.id,entry);
    const s=setup({async fetch(){throw new Error('offline');},cancel(){}},store);
    await s.controller.load(guangzhou); assert.equal(s.last().report,undefined);
  }
});
test('switching cities clears previous-city weather while loading', async () => {
  const s=setup(); await s.controller.load(guangzhou);
  const gate=deferred(); s.source.fetch=() => gate.promise; const next=s.controller.load(beijing);
  assert.equal(s.last().status,'loading'); assert.equal(s.last().report,undefined);
  gate.resolve(fixture()); await next; assert.equal(s.last().report.cityId,beijing.id);
});
test('late response from old city cannot overwrite new city', async () => {
  const a=deferred(),b=deferred(); let count=0;
  const s=setup({fetch(){return ++count===1?a.promise:b.promise;},cancel(){}});
  const one=s.controller.load(guangzhou); await tick();
  const two=s.controller.load(beijing); await tick();
  b.resolve(fixture()); await two; a.resolve(fixture()); await one;
  assert.equal(s.last().report.cityId,beijing.id); assert.equal(s.storage.cache.has(guangzhou.id),false);
});
test('late failure from old request cannot replace successful new city', async () => {
  const a=deferred(); let count=0;
  const s=setup({fetch(){return ++count===1?a.promise:Promise.resolve(fixture());},cancel(){}});
  const one=s.controller.load(guangzhou); await tick(); await s.controller.load(beijing);
  a.reject(new Error('late')); await one; assert.equal(s.last().status,'success'); assert.equal(s.last().report.cityId,beijing.id);
});
test('dispose ignores pending requests and permits a later page load', async () => {
  const gate=deferred(); const s=setup({fetch(){return gate.promise;},cancel(){}});
  const pending=s.controller.load(guangzhou); await tick(); s.controller.dispose();
  gate.resolve(fixture()); await pending; assert.equal(s.states.length,1);
  s.source.fetch=async()=>fixture(); await s.controller.load(beijing); assert.equal(s.last().status,'success');
});
test('retry recovers from a failed request for the same city', async () => {
  let count=0; const s=setup({async fetch(){if(++count===1)throw new Error('fail'); return fixture();},cancel(){}});
  await s.controller.load(beijing); assert.equal(s.last().status,'error'); await s.controller.retry();
  assert.equal(s.last().status,'success'); assert.equal(s.last().report.cityId,beijing.id);
});
test('cache failures do not hide successfully loaded weather', async () => {
  const store=memory(); store.fail=true; const s=setup(undefined,store); await s.controller.load(guangzhou);
  assert.equal(s.last().status,'success'); assert.ok(s.last().storageWarning.length);
});
test('invalid payload cannot replace a good cached forecast', async () => {
  const store=memory(); const original={cityId:guangzhou.id,raw:fixture(),savedAt:Date.now()-1000}; store.cache.set(guangzhou.id,original);
  const s=setup({async fetch(){return '{}';},cancel(){}},store); await s.controller.load(guangzhou);
  assert.equal(s.last().status,'error'); assert.equal(s.last().cached,true); assert.equal(store.cache.get(guangzhou.id),original);
});
test('Preferences cache survives store recreation and isolates cities', async () => {
  prefValues.clear(); const store=new WeatherStore({}); await store.select(guangzhou.id);
  await store.write({cityId:guangzhou.id,raw:fixture(),savedAt:100});
  const reopened=new WeatherStore({}); assert.equal(reopened.lastCity(),guangzhou.id);
  assert.equal(reopened.read(guangzhou.id).savedAt,100); assert.equal(reopened.read(beijing.id),undefined);
});
test('Preferences cache is bounded to 12 recent cities', async () => {
  prefValues.clear(); const store=new WeatherStore({});
  for (let i=0;i<15;i++) await store.write({cityId:String(i),raw:fixture(),savedAt:i});
  assert.equal(JSON.parse(prefValues.get('cities')).length,12); assert.equal(store.read('0'),undefined);
  assert.equal(store.read('14').savedAt,14);
});
test('corrupt Preferences cache can recover without discarding last city', async () => {
  prefValues.set('cities','{'); const store=new WeatherStore({}); await store.select(beijing.id);
  await store.write({cityId:guangzhou.id,raw:fixture(),savedAt:1});
  assert.equal(store.read(guangzhou.id).savedAt,1); assert.equal(store.lastCity(),beijing.id);
});
test('Preferences write errors reach the controller instead of silent success', async () => {
  failStorage=true; await assert.rejects(new WeatherStore({}).write({cityId:'x',raw:fixture(),savedAt:1})); failStorage=false;
});
function liveGet(url) {
  return new Promise((resolve,reject) => {
    const request=https.get(url,{timeout:20000},response => {
      let raw=''; response.setEncoding('utf8'); response.on('data',chunk => { raw+=chunk; });
      response.on('end',() => response.statusCode===200 ? resolve(raw) : reject(new Error('HTTP '+response.statusCode)));
    }); request.on('timeout',() => request.destroy(new Error('Live API timeout'))); request.on('error',reject);
  });
}
if(process.argv.includes('--live')) test('LIVE Guangzhou and Beijing API responses parse with seven days',async()=>{
  for(const city of [guangzhou,beijing]) {
    const raw=await liveGet(httpModule.weatherUrl(city)); const r=data.parseWeather(raw,city);
    assert.equal(r.days.length,7); assert.notEqual(r.temperature,'—');
    console.log(`LIVE ${city.name}: ${r.observedAt}, ${r.temperature}, ${r.condition}, ${r.days.length} days`);
  }
});
(async()=>{
  let passed=0;
  for(const t of tests) {
    let timer;
    try {
      await Promise.race([Promise.resolve().then(t.run), new Promise((_,reject) => {
        timer=setTimeout(()=>reject(new Error('Test timed out')),t.name.startsWith('LIVE')?45000:5000);
      })]);
      passed++; console.log('PASS '+t.name);
    }
    catch(error) { console.error('FAIL '+t.name,error); process.exitCode=1; }
    finally { clearTimeout(timer); offline=false; probeError=false; failStorage=false; handler=async()=>({responseCode:200,result:fixture()}); }
  }
  console.log(`Weather: ${passed}/${tests.length} passed`);
})();
