import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
test('push enabled state survives reload and explicit disable removes subscription',async()=>{
 const storage=new Map();let subscription=null;
 const notification={permission:'granted',requestPermission:async()=>notification.permission};
 const reg={active:true,pushManager:{getSubscription:async()=>subscription,subscribe:async()=>subscription={toJSON:()=>({endpoint:'https://fcm.googleapis.com/developer-test'}),unsubscribe:async()=>{subscription=null;return true;}}}};
 const context={URL,setTimeout,clearTimeout,crypto:{randomUUID:()=> 'device-test'},document:{baseURI:'http://localhost:7365/'},Notification:notification,localStorage:{getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},navigator:{serviceWorker:{register:async()=>reg}}};
 context.window={TONGYEOK_PUSH_PUBLIC_KEY:'public-test',PushManager:{},Notification:notification};
 vm.runInNewContext(readFileSync('web/push-client.js','utf8'),context);
 assert.equal(await context.window.tongyeokPushState('developer'),'off');
 assert.equal(JSON.parse(await context.window.tongyeokPushEnable('developer')).deviceId,'device-test');
 assert.equal(await context.window.tongyeokPushState('developer'),'enabled');
 assert.equal(await context.window.tongyeokPushState('other'),'off');
 await context.window.tongyeokPushDisable('developer');
 assert.equal(await context.window.tongyeokPushState('developer'),'off');
 notification.permission='denied';assert.equal(await context.window.tongyeokPushState('developer'),'denied');
});
