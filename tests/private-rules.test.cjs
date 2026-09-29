const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const script=fs.readFileSync(path.join(__dirname,'../WCRechargeIOS/Resources/private-rules.js'),'utf8');
const rules=JSON.parse(fs.readFileSync(path.join(__dirname,'rule-fixture.json'),'utf8'));
const requests=[];
class XHR {open(method,url,async=true){this.method=method;this.url=url;this.async=async;} send(body){this.body=body;requests.push(this);return 'sent';}}
const calls=[];
let enabled=false, applied=0;
const ctx={WCRuleState:{isEnabled:()=>enabled,recordApplied:()=>applied++},XMLHttpRequest:XHR,URLSearchParams,Request,WeakMap,fetch:function(...args){calls.push(args);return Promise.resolve('ok');}};
ctx.window=ctx;vm.createContext(ctx);vm.runInContext(script,ctx);const originalHook=XHR.prototype.send;vm.runInContext(script,ctx);assert.equal(XHR.prototype.send,originalHook);
function expected(url,body){for(const rule of rules)if(url.includes(rule.match))for(const [a,b] of rule.replacements)body=body.split(a).join(b);return body;}
(async()=>{
 const probe=new XHR();const testUrl='https://test.invalid/'+rules[0].match, testBody=rules[0].replacements[0][0];
 probe.open('POST',testUrl);probe.send(testBody);assert.equal(probe.body,testBody);assert.equal(applied,0);
 enabled=true;
 for(const rule of rules){
  const url='https://test.invalid/'+rule.match;
  const body=rule.replacements.map(x=>x[0]).join('&')+'&keep=unchanged';
  const xhr=new XHR();xhr.open('POST',url,false);assert.equal(xhr.send(body),'sent');assert.equal(xhr.body,expected(url,body));assert.equal(xhr.async,false);
  // Reopened objects must match the current URL, not the previous one.
  xhr.open('POST','https://test.invalid/unmatched');xhr.send(body);assert.equal(xhr.body,body);
  const init={method:'POST',body,credentials:'include',headers:{'X-Test':'same'}};
  await ctx.fetch(url,init);let call=calls.at(-1);assert.equal(call[1].body,expected(url,body));assert.equal(call[1].headers,init.headers);assert.equal(init.body,body);
  const params=new URLSearchParams(body);await ctx.fetch(url,{method:'POST',body:params});call=calls.at(-1);assert.equal(call[1].body.toString(),expected(url,params.toString()));
  const req=new Request(url,{method:'POST',body,credentials:'include',redirect:'manual',headers:{'content-type':'application/x-www-form-urlencoded','X-Test':'same'}});
  await ctx.fetch(req);call=calls.at(-1);assert.equal(await call[0].clone().text(),expected(url,body));assert.equal(call[0].credentials,'include');assert.equal(call[0].redirect,'manual');assert.equal(call[0].headers.get('X-Test'),'same');assert.equal(req.bodyUsed,false);
  const untouched={method:'POST',body:'no_matching_parameter=1'};await ctx.fetch(url,untouched);assert.equal(calls.at(-1)[1],untouched);
 }
 const binary=new Uint8Array([1,2,3]);const init={method:'POST',body:binary};await ctx.fetch('https://test.invalid/'+rules[0].match,init);assert.equal(calls.at(-1)[1],init);
 const init2={method:'POST',body:rules[0].replacements[0][0]};await ctx.fetch('https://test.invalid/no_match',init2);assert.equal(calls.at(-1)[1],init2);
 const x=new XHR();x.open('GET','https://test.invalid/plain');x.send();assert.equal(x.body,undefined);
 assert.ok(applied>0);
 enabled=false;const before=applied;
 await ctx.fetch(testUrl,{method:'POST',body:testBody});assert.equal(calls.at(-1)[1].body,testBody);assert.equal(applied,before);
 probe.send(testBody);assert.equal(probe.body,testBody);
 console.log('Private rule tests passed: matching, literal replacement, isolation, XHR, fetch, Request, URLSearchParams, repeat installation.');
})().catch(e=>{console.error(e);process.exit(1)});
