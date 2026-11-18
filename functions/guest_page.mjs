// No Firebase login, ad SDK, local history or third-party scripts on guest web.
export const guestPage=String.raw`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>통역톡 · 비회원 손님</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f5f9f9;color:#172b2b;font:17px/1.6 system-ui,sans-serif}main{max-width:620px;margin:auto;background:white;min-height:100dvh;display:flex;flex-direction:column}header{padding:18px 20px;border-bottom:1px solid #e4eded;display:flex;align-items:center;gap:12px}h1{font-size:23px;margin:0;flex:1}.badge{color:#176d68;background:#e3f3ef;border:1px solid #b2d6ce;padding:3px 9px;border-radius:8px;font-size:13px}.notice{background:#edf7f4;border-radius:12px;margin:14px 16px;padding:14px;color:#255c55}.notice p{margin:4px 0}#messages{flex:1;padding:4px 16px 16px;overflow-wrap:anywhere}.bubble{max-width:85%;background:#f1f3f5;border-radius:16px;padding:12px 15px;margin:12px 0;white-space:pre-wrap}.mine{margin-left:auto;background:#207b72;color:white}.small{font-size:13px;opacity:.8}.error{color:#a12929;padding:0 16px}form{padding:14px 16px;border-top:1px solid #e2eded;background:white;position:sticky;bottom:0;display:flex;gap:8px;align-items:end}textarea,input{font:inherit;border:1px solid #c5d7d1;border-radius:12px;padding:12px;width:100%;background:white}textarea{resize:none;min-height:52px;max-height:150px}button{font:inherit;cursor:pointer;background:#207b72;color:white;border:0;border-radius:12px;padding:11px 16px}button:disabled{opacity:.45;cursor:default}.plain{background:transparent;color:#207b72;padding:4px;font-size:14px}#entry{padding:8px 20px}#entry button{width:100%;margin:14px 0}#entry label{display:block}.hidden{display:none!important}#ended{padding:24px}#count{text-align:right}.input-wrap{flex:1}label.accept{display:flex;gap:10px;font-size:15px;margin-top:12px}.accept input{width:22px;flex-shrink:0}</style>
<main><header><h1>통역톡</h1><span class="badge">비회원 손님</span><button id="end" class="plain hidden">대화 종료</button></header>
<div class="notice"><strong>가입 없이 현재 대화에 참여합니다.</strong><p>대화 종료 후 지난 대화를 다시 볼 수 없습니다.</p><p class="small">기록은 상대방 회원의 휴대폰에 남습니다. 번역비는 초대한 회원이 부담합니다.</p></div>
<section id="entry"><h2>번역 대화 시작</h2><p>한국어로 입력하면 상대방에게 몽골어로 전달됩니다.</p><label>대화에 표시할 이름<input id="name" maxlength="30" autocomplete="off" placeholder="이름 또는 별명"></label><label class="accept"><input id="accept" type="checkbox">대화 종료 후 다시 볼 수 없으며, 상대방 회원에게 기록이 남는 것을 확인했습니다.</label><button id="join" disabled>동의하고 대화 시작</button><p class="small">초대 링크는 한 사람만 사용할 수 있고 발급 후 24시간 안에 대화를 마쳐 주세요.</p></section>
<div id="title" class="notice hidden"></div><div id="error" class="error" role="alert"></div><div id="messages" class="hidden" aria-live="polite"></div>
<section id="ended" class="hidden"><h2>대화가 종료되었습니다</h2><p>지난 대화는 다시 볼 수 없습니다. 다시 대화하려면 회원에게 새 초대를 요청해 주세요.</p></section>
<form id="send" class="hidden"><div class="input-wrap"><textarea id="text" rows="1" placeholder="메시지 입력" aria-label="메시지 입력"></textarea><div id="count" class="small">0/50</div></div><button id="sendButton" disabled>전송</button></form></main>
<script>
(()=>{'use strict';const $=id=>document.getElementById(id);const root=location.pathname.replace(/\/guest\/?$/,'');const id=new URLSearchParams(location.search).get('room');const params=new URLSearchParams(location.hash.slice(1));let invite=params.get('invite');let token=null,timer=null,busy=false,closed=false;
const storageKey='tt-active-guest-'+id;
try{token=sessionStorage.getItem(storageKey);}catch{}
history.replaceState(null,'',location.pathname+location.search); // secret never stays in URL/history/referrer
function fail(e){$('error').textContent=({no_credit:'초대한 회원의 번역권이 부족합니다.',rate_limited:'잠시 후 다시 보내 주세요.',session_closed:'종료되었거나 사용할 수 없는 초대입니다.',session_limit:'이 대화의 메시지 한도에 도달했습니다.',unauthenticated:'초대를 다시 확인해 주세요.'})[e.message]||'연결하지 못했습니다. 잠시 후 다시 시도해 주세요.';}
async function api(action,body){const r=await fetch(root+'/guest-api/'+action,{method:'POST',headers:{'Content-Type':'application/json',...(token?{'Authorization':'Bearer '+token}:{})},body:JSON.stringify({id,...body}),cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'});const data=await r.json();if(!r.ok)throw Error(data.error||'network');return data;}
function finish(){closed=true;clearTimeout(timer);token=null;invite=null;try{sessionStorage.removeItem(storageKey);}catch{}$('messages').replaceChildren();for(const x of ['entry','messages','title','send','end'])$(x).classList.add('hidden');$('ended').classList.remove('hidden');$('error').textContent='';}
let renderedMessages='';
const expandedMessages=new Set();
function renderMessages(messages){
 const snapshot=JSON.stringify(messages);
 if(snapshot===renderedMessages)return;
 renderedMessages=snapshot;
 const nearBottom=innerHeight+scrollY>=document.body.scrollHeight-160;
 const bubbles=messages.map(message=>{
  const mine=message.sender==='guest';
  const translated=message.status==='done'&&Boolean(message.translation);
  const failed=message.status==='failed';
  const bubble=document.createElement('div');
  bubble.className='bubble'+(mine?' mine':'');
  const primary=document.createElement('div');
  primary.textContent=mine?message.original:translated?message.translation:failed?'번역하지 못했습니다.':'번역 중…';
  bubble.append(primary);
  if(translated){
   const toggle=document.createElement('button');
   toggle.type='button';
   toggle.className='plain';
   toggle.style.color='inherit';
   const secondary=document.createElement('div');
   secondary.className='small';
   secondary.id='message-detail-'+message.id;
   secondary.textContent=mine?message.translation:message.original;
   toggle.setAttribute('aria-controls',secondary.id);
   function updateExpansion(){
    const expanded=expandedMessages.has(message.id);
    secondary.hidden=!expanded;
    toggle.setAttribute('aria-expanded',String(expanded));
    toggle.textContent=expanded?'접기':mine?'번역문 보기':'원문 보기';
   }
   toggle.onclick=()=>{
    if(!expandedMessages.delete(message.id))expandedMessages.add(message.id);
    updateExpansion();
   };
   updateExpansion();
   bubble.append(toggle,secondary);
  }
  return bubble;
 });
 $('messages').replaceChildren(...bubbles);
 if(nearBottom)scrollTo(0,document.body.scrollHeight);
}
async function poll(){if(closed)return;try{const data=await api('read',{});if(data.status!=='active'){finish();return;}$('title').textContent=data.ownerName+'님과 대화';$('title').classList.remove('hidden');renderMessages(data.messages);$('error').textContent='';}catch(e){if(['session_closed','unauthenticated'].includes(e.message)){finish();return;}fail(e);}timer=setTimeout(poll,4000);}
function showChat(){$('entry').classList.add('hidden');for(const x of ['messages','send','end'])$(x).classList.remove('hidden');poll();}
$('accept').onchange=()=>{$('join').disabled=!$('accept').checked;};
$('join').onclick=async()=>{if(busy)return;busy=true;$('join').disabled=true;try{const data=await api('join',{secret:invite,name:$('name').value,confirmed:$('accept').checked});token=data.token;invite=null;try{sessionStorage.setItem(storageKey,token);}catch{}showChat();}catch(e){fail(e);}finally{busy=false;$('join').disabled=!$('accept').checked;}};
$('text').oninput=()=>{const n=[...$('text').value].length;$('count').textContent=n+'/50';$('sendButton').disabled=busy||n>50||!$('text').value.trim();};
let pendingId=null,pendingText=null;
$('send').onsubmit=async e=>{e.preventDefault();if(busy||closed)return;const text=$('text').value;if(!text.trim()||[...text].length>50)return;if(pendingText!==text){pendingId=crypto.randomUUID();pendingText=text;}busy=true;$('text').oninput();try{await api('send',{messageId:pendingId,text});pendingId=null;pendingText=null;$('text').value='';clearTimeout(timer);await poll();}catch(e){if(e.message==='session_closed')finish();else fail(e);}finally{busy=false;$('text').oninput();}};
$('end').onclick=async()=>{if(!confirm('대화를 종료할까요? 종료 후 지난 대화는 다시 볼 수 없습니다.'))return;try{await api('end',{});finish();}catch(e){fail(e);}};
if(!/^[a-f0-9]{40}$/.test(id||'')){fail(Error('session_closed'));$('join').disabled=true;}else if(token){showChat();}else if(!invite){finish();}
})();</script></html>`;
