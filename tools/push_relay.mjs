// Private operator process: never place credentials or VAPID private keys in this repo.
// Trial only: the developer PC and this process must stay running.
import {Firestore,Timestamp,FieldValue} from '@google-cloud/firestore';
import {GoogleAuth,OAuth2Client} from 'google-auth-library';
import webpush from 'web-push';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const projectId = 'tongyeok-talk-lab-20261024';
if (process.env.TONGYEOK_PROJECT !== projectId) throw new Error('Explicit isolated project guard required');
const vapid = JSON.parse(readFileSync(process.env.TONGYEOK_VAPID_FILE, 'utf8'));
const credentialModule = await import(process.env.TONGYEOK_OPERATOR_AUTH_MODULE);
const credential = await credentialModule.default();
const authClient = new OAuth2Client();
authClient.refreshHandler = async () => { const token = await credential.getAccessToken(); return {access_token:token.access_token, expiry_date:Date.now()+240000}; };
const db = new Firestore({projectId, auth:new GoogleAuth({authClient, projectId})});
webpush.setVapidDetails('https://dntprbs-maker.github.io/tongyeok-talk/', vapid.publicKey, vapid.privateKey);
const since = Timestamp.now(), watching = new Map(), inflight = new Set();
let success = 0, failures = 0;
const allowed = host => host === 'fcm.googleapis.com' || host === 'updates.push.services.mozilla.com' || host.endsWith('.push.services.mozilla.com') || host === 'web.push.apple.com';
async function deliver(room, message) {
  const data = message.data();
  if (!data.timestamp || data.timestamp.compareTo(since) < 0) return;
  const participants = room.data().participants || [];
  // Allow the active room's visible-message receipt to reach the server first.
  await new Promise(resolve => setTimeout(resolve, 1200));
  for (const uid of participants.filter(uid => uid !== data.senderId)) {
    const receipt = await room.ref.collection('reads').doc(uid).get();
    if (receipt.data()?.readThrough?.compareTo(data.timestamp) >= 0) continue;
    const devices = await db.collection('users').doc(uid).collection('pushDevices').where('enabled','==',true).get();
    for (const device of devices.docs) {
      const id = createHash('sha256').update(`${room.id}/${message.id}/${uid}/${device.id}`).digest('hex');
      if (inflight.has(id)) continue;
      inflight.add(id);
      try {
        const dispatch = db.collection('_pushDispatch').doc(id);
        if ((await dispatch.get()).data()?.status === 'sent') continue;
        const sub = JSON.parse(device.data().subscriptionJson), url = new URL(sub.endpoint);
        if (url.protocol !== 'https:' || !allowed(url.hostname) || url.username || url.password || url.port) throw new Error('endpoint_rejected');
        for (let attempt=0; attempt<3; attempt++) {
          try {
            await webpush.sendNotification(sub, JSON.stringify({conversationId:room.id,language:device.data().language}), {TTL:300, urgency:'high', timeout:15000});
            await dispatch.set({status:'sent', sentAt:FieldValue.serverTimestamp()});
            success++; console.log(JSON.stringify({event:'push_accepted', success, failures}));
            break;
          } catch (error) {
            if ([404,410].includes(error.statusCode)) { await device.ref.update({enabled:false,updatedAt:FieldValue.serverTimestamp()}); break; }
            if (attempt === 2 || (error.statusCode && error.statusCode < 500 && error.statusCode !== 429)) throw error;
            await new Promise(resolve => setTimeout(resolve, (attempt+1)*2000));
          }
        }
      } catch (error) { failures++; console.error(JSON.stringify({event:'push_failed',code:error.statusCode||'internal',success,failures})); }
      finally { inflight.delete(id); }
    }
  }
}
const stop = db.collection('conversations').onSnapshot(snapshot => {
  for (const change of snapshot.docChanges()) {
    const room = change.doc;
    if (change.type === 'removed') { watching.get(room.id)?.(); watching.delete(room.id); continue; }
    if (watching.has(room.id)) continue;
    watching.set(room.id, room.ref.collection('messages').where('timestamp','>=',since).onSnapshot(messages => {
      for (const item of messages.docChanges()) if (item.type === 'added') deliver(room,item.doc).catch(() => { failures++; console.error(JSON.stringify({event:'delivery_failed', failures})); });
    }, error => console.error(JSON.stringify({event:'message_listener_failed',code:error.code}))));
  }
}, error => { console.error(JSON.stringify({event:'room_listener_failed',code:error.code})); process.exitCode=1; });
console.log(JSON.stringify({event:'relay_started',projectId,startedAt:new Date().toISOString(),mode:'local-PC trial; no cloud billing'}));
function shutdown(){stop();for(const unsubscribe of watching.values())unsubscribe();db.terminate().finally(()=>process.exit());}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
