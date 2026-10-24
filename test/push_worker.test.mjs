import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
test('background worker shows a private localized notification and click opens app',async()=>{
 const handlers={},shown=[],opened=[];let waited;
 const self={addEventListener:(k,f)=>handlers[k]=f,skipWaiting(){},registration:{scope:'https://dntprbs-maker.github.io/tongyeok-talk/push/',showNotification:async(t,o)=>shown.push({t,o})},clients:{claim:async()=>{},matchAll:async()=>[],openWindow:async url=>opened.push(url)}};
 vm.runInNewContext(readFileSync('web/tongyeok-push-sw.js','utf8'),{self,URL});
 handlers.push({data:{json:()=>({language:'mn',conversationId:'room'})},waitUntil:p=>waited=p});await waited;
 assert.equal(shown[0].t,'Орчуулагч Ток');assert.equal(shown[0].o.tag,'tongyeok-room');assert.ok(!JSON.stringify(shown).includes('originalText'));
 handlers.notificationclick({notification:{close(){}},waitUntil:p=>waited=p});await waited;
 assert.equal(opened[0],'https://dntprbs-maker.github.io/tongyeok-talk/');
});
