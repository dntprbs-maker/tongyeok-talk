import {createGuestRoom,joinGuestRoom,readGuestRoom,sendGuestMessage,endGuestRoom,acknowledgeGuestArchive} from './guest_chat.mjs';
import {guestPage} from './guest_page.mjs';
export async function guestHttp(req,res,{db,authenticate}){
 const url=new URL(req.url,'https://localhost');
 if(!url.pathname.startsWith('/guest'))return false;
 res.setHeader('Cache-Control','no-store');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('X-Content-Type-Options','nosniff');
 if(url.pathname.startsWith('/guest-api/')&&req.headers.origin==='https://dntprbs-maker.github.io'){
  res.setHeader('Access-Control-Allow-Origin',req.headers.origin);res.setHeader('Vary','Origin');
  res.setHeader('Access-Control-Allow-Headers','Authorization,Content-Type');res.setHeader('Access-Control-Allow-Methods','POST,OPTIONS');
  if(req.method==='OPTIONS'){res.writeHead(204);res.end();return true;}
 }
 if(url.pathname==='/guest'&&req.method==='GET'){
  res.setHeader('Content-Security-Policy',"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});res.end(guestPage);return true;
 }
 try{
  if(req.method!=='POST')throw Error('invalid_request');
  let body=req.body;if(!body||typeof body==='string'||Buffer.isBuffer(body)){let raw=body?.toString()??'';if(!raw)for await(const chunk of req){raw+=chunk;if(Buffer.byteLength(raw)>18000)throw Error('invalid_request');}body=JSON.parse(raw);}
  if(!body||typeof body!=='object'||Array.isArray(body))throw Error('invalid_request');
  const action=url.pathname.replace('/guest-api/','');
  const fields={create:[],join:['id','secret','name','confirmed'],read:['id'],send:['id','text','messageId'],end:['id'],ack:['id','ids']};
  if(!fields[action]||Object.keys(body).some(k=>!fields[action].includes(k)))throw Error('invalid_request');
  const token=req.headers.authorization?.replace(/^Bearer /,'');let uid;
  if(action!=='join'&&token&&!/^[a-f0-9]{64}$/.test(token)){try{uid=(await authenticate(token)).uid;}catch{/* An opaque guest token is checked only inside its session. */}}
  if(['create','ack'].includes(action)&&!uid)throw Error('unauthenticated');
  const identity={uid,token};let result;
  if(action==='create')result=await createGuestRoom(db,uid,{pilotOnly:true});
  if(action==='join'){if(body.confirmed!==true)throw Error('invalid_request');result=await joinGuestRoom(db,body.id,body);}
  if(action==='read')result=await readGuestRoom(db,body.id,identity);
  if(action==='send')result=await sendGuestMessage(db,body.id,identity,body);
  if(action==='end')result=await endGuestRoom(db,body.id,identity);
  if(action==='ack')result=await acknowledgeGuestArchive(db,body.id,uid,body.ids);
  res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
 }catch(e){const known=['invalid_request','unauthenticated','session_closed','rate_limited','no_credit','mongolian_member_required','pilot_only','session_limit','translation_pending'];const code=known.includes(e.message)?e.message:'unavailable';res.writeHead(code==='unauthenticated'?401:code==='session_closed'?410:code==='unavailable'?503:400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:code}));}
 return true;
}
