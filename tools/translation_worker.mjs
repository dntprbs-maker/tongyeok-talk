// Single-PC trial worker. Only the isolated project; key stays outside repository.
import {readFileSync,mkdirSync,appendFileSync,existsSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {FieldValue,Timestamp} from '@google-cloud/firestore';
import {operatorFirestore} from './operator_firestore.mjs';
import {config,translate} from './translation_provider.mjs';
import {compareTimestamps} from './push_helpers.mjs';
const apiKey=readFileSync(process.env.TONGYEOK_OPENROUTER_KEY_FILE,'utf8').trim();
if(!apiKey.startsWith('sk-or-v1-'))throw new Error('invalid_private_key_file');
const db=await operatorFirestore(),since=Timestamp.now(),watching=new Map(),pending=new Set();
const directory=resolve('artifacts/chat-translations');mkdirSync(directory,{recursive:true});
const ledgerFile=resolve(directory,'budget.json');
const budget=existsSync(ledgerFile)?JSON.parse(readFileSync(ledgerFile,'utf8')):{calls:0,costUsd:0};
const auditFile=resolve(directory,'audit.jsonl');
let queue=Promise.resolve(),ready=false;
function health(){if(process.env.TONGYEOK_TRANSLATION_HEALTH_FILE)writeFileSync(process.env.TONGYEOK_TRANSLATION_HEALTH_FILE,JSON.stringify({pid:process.pid,ready,calls:budget.calls,costUsd:budget.costUsd,checkedAt:new Date().toISOString()}));}
function enqueue(ref,retry=false){
  if(pending.has(ref.path))return;
  pending.add(ref.path);queue=queue.then(()=>processMessage(ref,retry)).catch(()=>console.error('translation_worker_internal_error')).finally(()=>pending.delete(ref.path));
}
async function processMessage(ref,retry){
  const doc=await ref.get();if(!doc.exists)return;
  const data=doc.data();
  if(data.translationStatus==='done'||(!retry&&(!data.timestamp||compareTimestamps(data.timestamp,since)<0)))return;
  if(!['ko','mn'].includes(data.sourceLang)||typeof data.originalText!=='string'||!data.originalText.trim()||[...data.originalText].length>2000)return;
  const attempt=(data.translationAttempts||0)+1;
  if(attempt>3)return;
  if(budget.calls>=200||budget.costUsd>=0.25){await ref.update({translationStatus:'failed',translationError:'trial_budget_limit'});return;}
  await ref.update({translationStatus:'pending',translationAttempts:attempt,translationModel:config.selectedModel});
  const target=data.sourceLang==='ko'?'mn':'ko';
  const audit={testedAt:new Date().toISOString(),conversationId:ref.parent.parent.id,messageId:doc.id,source:data.sourceLang,target,original:data.originalText,attempt,model:config.selectedModel,review:'미검증'};
  // Reserve the call before sending. No network retries or fallback models.
  budget.calls++;writeFileSync(ledgerFile,JSON.stringify(budget));
  try{
    const result=await translate({model:config.selectedModel,text:data.originalText,source:data.sourceLang,target},{apiKey});
    if(result.actualModel!==config.selectedModel)throw new Error('unexpected_response_model');
    budget.costUsd+=result.costUsd??0;writeFileSync(ledgerFile,JSON.stringify(budget));
    Object.assign(audit,result,{status:'done'});
    // Audit first: every successful provider response is retained before publication.
    appendFileSync(auditFile,JSON.stringify(audit)+'\n');
    await ref.update({translations:{[data.sourceLang]:data.originalText,[target]:result.translation},translationStatus:'done',translationError:FieldValue.delete(),translationModel:result.actualModel,translatedAt:FieldValue.serverTimestamp()});
  }catch(error){
    audit.status='failed';audit.error=error.message;appendFileSync(auditFile,JSON.stringify(audit)+'\n');
    await ref.update({translationStatus:'failed',translationError:error.message});
  }
  health();console.log(JSON.stringify({event:'translation_processed',status:audit.status,calls:budget.calls,costUsd:budget.costUsd}));
}
db.collection('conversations').onSnapshot(snapshot=>{
  ready=true;health();
  for(const change of snapshot.docChanges()){
    const room=change.doc;if(change.type==='removed')continue;
    if(watching.has(room.id))continue;
    const stopMessages=room.ref.collection('messages').where('timestamp','>=',since).onSnapshot(messages=>{
      for(const message of messages.docChanges())if(message.type==='added')enqueue(message.doc.ref);
    },()=>console.error('translation_messages_listener_error'));
    const stopRetries=room.ref.collection('translationRetries').where('requestedAt','>=',since).onSnapshot(requests=>{
      for(const request of requests.docChanges())if(request.type==='added'){
        const mid=request.doc.data().messageId;
        if(typeof mid==='string'&&!mid.includes('/'))enqueue(room.ref.collection('messages').doc(mid),true);
      }
    },()=>console.error('translation_retry_listener_error'));
    watching.set(room.id,()=>{stopMessages();stopRetries();});
  }
},()=>console.error('translation_rooms_listener_error'));
setInterval(health,30000);
