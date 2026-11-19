// Native notifications share the isolated project's account; never accept a URL from a token.
export function nativeMessage(subscription, {language, conversationId}) {
  if(subscription.transport!=='fcm'||typeof subscription.token!=='string'||subscription.token.length<20||subscription.token.length>4096||!/^[A-Za-z0-9_:\-]+$/.test(subscription.token))throw Error('invalid_native_push_token');
  const mn=language==='mn';
  return {message:{token:subscription.token,
    notification:{title:mn?'Орчуулагч Ток':'통역톡',body:mn?'Шинэ зурвас ирлээ. Чатаа нээж шалгана уу.':'새 메시지가 도착했어요. 대화 목록에서 확인해 주세요.'},
    data:{conversationId},android:{priority:'high',ttl:'300s',notification:{channel_id:'tongyeok_messages',tag:'tongyeok-'+conversationId}},
    apns:{headers:{'apns-priority':'10','apns-push-type':'alert'},payload:{aps:{sound:'default'}}}}};
}
export async function sendNativePush(subscription,data,{authClient,fetcher=fetch}={}) {
 const body=nativeMessage(subscription,data);
 const {token}=await authClient.getAccessToken();
 if(!token)throw Error('native_push_operator_auth_missing');
 const r=await fetcher('https://fcm.googleapis.com/v1/projects/tongyeok-talk-lab-20261024/messages:send',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 if(!r.ok){const e=new Error('native_push_http_'+r.status);e.statusCode=r.status;throw e;}
}
