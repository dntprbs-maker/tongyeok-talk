import {createHash} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import webpush from 'web-push';
import {getMessaging} from 'firebase-admin/messaging';
import {nativeMessage} from './worker_common/native_push.mjs';
import {compareTimestamps} from './worker_common/push_helpers.mjs';

export async function processCloudPush(db,snapshot,{vapid,allowedUids,sendNative=msg=>getMessaging().send(msg)}={}){
  const data=snapshot.data(),room=await snapshot.ref.parent.parent.get();
  if(!room.exists||!(room.data().participants??[]).includes(data.senderId))return;
  // Give visible-message read receipts the same grace period as the PC relay.
  await new Promise(r=>setTimeout(r,1200));
  for(const uid of (room.data().participants??[]).filter(u=>u!==data.senderId&&(!allowedUids||allowedUids.includes(u)))){
    const read=(await room.ref.collection('reads').doc(uid).get()).data()?.readThrough;
    if(read&&compareTimestamps(read,data.timestamp)>=0)continue;
    const devices=await db.collection(`users/${uid}/pushDevices`).where('enabled','==',true).get();
    for(const device of devices.docs){
      const id=createHash('sha256').update(`${room.id}/${snapshot.id}/${uid}/${device.id}`).digest('hex');
      const dispatch=db.doc('_pushDispatch/'+id);
      const acquired=await db.runTransaction(async tx=>{
        const old=(await tx.get(dispatch)).data();
        if(old?.status==='sent'||old?.status==='sending')return false;
        tx.set(dispatch,{status:'sending',startedAt:FieldValue.serverTimestamp()});return true;
      });
      if(!acquired)continue;
      try{
        const sub=JSON.parse(device.data().subscriptionJson),language=device.data().language;
        if(sub.transport==='fcm'){
          const {message}=nativeMessage(sub,{language,conversationId:room.id});
          await sendNative(message);
        }else{
          const url=new URL(sub.endpoint);
          if(url.protocol!=='https:'||url.username||url.password||url.port||!(url.hostname==='fcm.googleapis.com'||url.hostname==='web.push.apple.com'||url.hostname==='updates.push.services.mozilla.com'||url.hostname.endsWith('.push.services.mozilla.com')))throw Error('endpoint_rejected');
          await webpush.sendNotification(sub,JSON.stringify({conversationId:room.id,language}),{TTL:300,urgency:'high',timeout:15000,vapidDetails:{subject:'https://dntprbs-maker.github.io/tongyeok-talk/',publicKey:vapid.publicKey,privateKey:vapid.privateKey}});
        }
        await dispatch.set({status:'sent',sentAt:FieldValue.serverTimestamp()});
        console.log(JSON.stringify({event:'cloud_push_accepted'}));
      }catch(e){
        const code=e.statusCode??e.code??'internal';
        await dispatch.set({status:'failed',code:String(code).slice(0,100),failedAt:FieldValue.serverTimestamp()});
        if([404,410].includes(e.statusCode)||['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(e.code))await device.ref.update({enabled:false,updatedAt:FieldValue.serverTimestamp()});
        console.error(JSON.stringify({event:'cloud_push_failed',code}));
      }
    }
  }
}
