// Explicit manual integration test. Synthetic developer accounts only.
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,signInWithEmailAndPassword,createUserWithEmailAndPassword} from 'firebase/auth';
import {getFirestore,doc,collection,writeBatch,getDoc,getDocs,query,where,serverTimestamp,setDoc,updateDoc,terminate,disableNetwork,enableNetwork,waitForPendingWrites} from 'firebase/firestore';
import {readFileSync,writeFileSync,existsSync,mkdirSync} from 'node:fs';
import {randomInt} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve('..'),out=resolve('artifacts/night-verification');mkdirSync(out,{recursive:true});
const configuration={apiKey:'AIzaSyB7Nf9kYgJ9y0ubRGrg3sHA5tLw2qTLDsg',projectId:'tongyeok-talk-lab-20261024'};
const sessions=[];
async function login(account,index){
 const app=initializeApp(configuration,'night-'+index+'-'+Date.now()),auth=getAuth(app),db=getFirestore(app);
 const email=`p${account.phone.slice(1)}@phone.tongyeok.invalid`;
 let user;
 if(account.create){user=(await createUserWithEmailAndPassword(auth,email,account.password)).user;const batch=writeBatch(db);
  batch.set(doc(db,'users',user.uid),{displayName:account.name,preferredLanguage:'Mongolian',createdAt:serverTimestamp()});
  batch.set(doc(db,'phoneDirectory',account.phone.slice(1)),{uid:user.uid});batch.set(doc(db,'users',user.uid,'private','contact'),{phoneE164:account.phone,phoneVerified:false});await batch.commit();
 }else user=(await signInWithEmailAndPassword(auth,email,account.password)).user;
 const session={app,auth,db,uid:user.uid,account};sessions.push(session);return session;
}
const ko=JSON.parse(readFileSync(resolve(root,'tongyeok-note10-test-account.json'),'utf8'));
const mnFile=resolve(root,'tongyeok-mongolian-test-account.json');
const mn=existsSync(mnFile)?JSON.parse(readFileSync(mnFile,'utf8')):{phone:'+821000009653',password:Array.from({length:24},()=>randomInt(10)).join(''),name:'Монгол хөгжүүлэлтийн туршилт',create:true};
if(!existsSync(mnFile))writeFileSync(mnFile,JSON.stringify(mn));
const result={startedAt:new Date().toISOString(),scope:'Real isolated Firebase + OpenRouter worker; SDK clients, phone UI reported separately',checks:{},messages:[]};
const record=()=>writeFileSync(resolve(out,'live-results.json'),JSON.stringify(result,null,2));
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function waitTranslated(ref,reader){
 for(let n=0;n<60;n++){const snapshot=await getDoc(doc(reader.db,ref.path));const data=snapshot.data();if(data?.translationStatus==='done')return {messageId:ref.id,...data,timestamp:data.timestamp.toDate().toISOString(),translatedAt:data.translatedAt?.toDate().toISOString()};if(data?.translationStatus==='failed')throw new Error('translation_failed:'+data.translationError);await sleep(1000);}
 throw new Error('translation_timeout');
}
async function send(sender,reader,room,text,source){const ref=doc(collection(sender.db,'conversations',room,'messages'));const batch=writeBatch(sender.db);batch.set(ref,{senderId:sender.uid,originalText:text,translations:{},sourceLang:source,timestamp:serverTimestamp()});batch.update(doc(sender.db,'conversations',room),{lastMessage:text,timestamp:serverTimestamp()});await batch.commit();const data=await waitTranslated(ref,reader);result.messages.push({conversationId:room,...data});record();return ref;}
try{
 const a=await login(ko,'ko');let b;
 try{b=await login(mn,'mn');}catch(error){if(error.code!=='auth/email-already-in-use')throw error;delete mn.create;b=await login(mn,'mn-recover');}
 delete mn.create;writeFileSync(mnFile,JSON.stringify(mn));
 await updateDoc(doc(a.db,'users',a.uid),{preferredLanguage:'Korean'});await updateDoc(doc(b.db,'users',b.uid),{preferredLanguage:'Mongolian'});
 result.checks.twoLanguages=(await getDoc(doc(a.db,'users',b.uid))).data().preferredLanguage==='Mongolian';
 result.checks.phoneLookup=(await getDoc(doc(a.db,'phoneDirectory',mn.phone.slice(1)))).data().uid===b.uid;
 const room=doc(collection(a.db,'conversations'));await setDoc(room,{participants:[a.uid,b.uid],isGroup:false,lastMessage:'',timestamp:serverTimestamp()});result.roomId=room.id;result.users={ko:a.uid,mn:b.uid};record();
 await send(a,b,room.id,'안녕하세요. 내일 오전 9시에 만나요.','ko');
 await send(b,a,room.id,'Сайн байна уу. Маргааш өглөө 9 цагт уулзъя.','mn');
 await send(a,b,room.id,'오늘은 3층부터 청소해 주세요. 바닥이 젖어 있으니 조심하세요.','ko');
 await send(b,a,room.id,'Би 30,000 вон шилжүүлсэн. Та шалгаад хэлээрэй.','mn');
 await send(a,b,room.id,'세제를 섞지 마세요. 작업이 끝나면 문을 잠가 주세요.','ko');
 result.checks.bothDirections=result.messages.some(r=>r.sourceLang==='ko')&&result.messages.some(r=>r.sourceLang==='mn');
 const last=(await getDocs(collection(b.db,'conversations',room.id,'messages'))).docs.sort((x,y)=>x.data().timestamp.toMillis()-y.data().timestamp.toMillis()).at(-1);
 await setDoc(doc(b.db,'conversations',room.id,'reads',b.uid),{readThrough:last.data().timestamp});result.checks.readReceipt=(await getDoc(doc(a.db,'conversations',room.id,'reads',b.uid))).exists();
 await disableNetwork(a.db);
 const offlineRef=doc(collection(a.db,'conversations',room.id,'messages'));
 const offlineBatch=writeBatch(a.db);offlineBatch.set(offlineRef,{senderId:a.uid,originalText:'인터넷이 다시 연결된 뒤 한 번만 도착해야 해요.',translations:{},sourceLang:'ko',timestamp:serverTimestamp()});offlineBatch.update(room,{lastMessage:'인터넷이 다시 연결된 뒤 한 번만 도착해야 해요.',timestamp:serverTimestamp()});
 const pending=offlineBatch.commit();await sleep(600);await enableNetwork(a.db);await pending;await waitForPendingWrites(a.db);
 const recovered=await waitTranslated(offlineRef,b);result.messages.push({conversationId:room.id,...recovered});
 result.checks.offlineReconnect=(await getDocs(query(collection(b.db,'conversations',room.id,'messages'),where('originalText','==','인터넷이 다시 연결된 뒤 한 번만 도착해야 해요.')))).size===1;
 const thirdAccount=JSON.parse(readFileSync(resolve(root,'tongyeok-talk-phone-test-accounts.json'),'utf8'))[0];const c=await login(thirdAccount,'third');
 const group=doc(collection(a.db,'conversations'));await setDoc(group,{participants:[a.uid,b.uid,c.uid],isGroup:true,groupName:'야간 번역 개발시험',lastMessage:'',timestamp:serverTimestamp()});result.groupId=group.id;
 await send(b,a,group.id,'Маргааш ажил хэдэн цагт эхлэх вэ?','mn');
 result.checks.groupThreeMembers=(await getDoc(doc(c.db,'conversations',group.id))).data().participants.length===3;
 result.checks.groupTranslation=(await getDocs(collection(c.db,'conversations',group.id,'messages'))).docs.every(d=>d.data().translations.ko&&d.data().translations.mn);
 const reload=await login(mn,'reopen');result.checks.historyAfterNewLogin=(await getDocs(collection(reload.db,'conversations',room.id,'messages'))).size===6;
 if(Object.values(result.checks).some(value=>value!==true))throw new Error('live_check_failed');
 result.finishedAt=new Date().toISOString();record();console.log(JSON.stringify({checks:result.checks,roomId:room.id,groupId:group.id,messages:result.messages.length}));
}finally{record();for(const s of sessions){await terminate(s.db);await deleteApp(s.app);}}
