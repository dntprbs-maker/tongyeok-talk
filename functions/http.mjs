import {createSession, grantReward, verifyCallback, googleKeys, TEST_UNIT,acknowledgeVerification} from './rewards.mjs';
import {requestAccountDeletion,deletionPolicy} from './account_deletion.mjs';
import {guestHttp} from './guest_http.mjs';
import {referralStatus, registerReferral} from './referrals.mjs';

const deletionHelp=`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>통역톡 계정 삭제 요청 · Бүртгэл устгах</title><style>body{font:18px/1.8 system-ui;max-width:800px;margin:40px auto;padding:20px;color:#192238}h1{font-size:28px}aside{padding:16px;background:#edf1ff}</style><h1>통역톡 계정 삭제 요청</h1><p>앱 설정 → 회원 탈퇴 요청에서 비밀번호로 본인 확인 후 요청할 수 있습니다.</p><p>앱을 사용할 수 없거나 이미 지운 경우 <a href="mailto:dntprbs@gmail.com?subject=통역톡%20계정%20삭제%20요청">dntprbs@gmail.com</a>으로 통역톡 가입 전화번호와 계정 삭제 요청임을 보내 주세요. 비밀번호·신분증을 보내지 마세요. 운영자가 계정 소유 여부를 확인하고 처리 방법과 완료 예상일을 안내합니다.</p><aside>완료 시 로그인 계정·전화번호 검색 정보·개인 알림 기기·이용권 잔량은 삭제됩니다. 상대방에게 전달된 대화의 원문과 번역문은 상대방 기록에 남고 이름은 ‘탈퇴한 사용자’로 표시됩니다. 이후 새로 가입해도 이전 계정의 대화에 다시 접근할 수 없습니다.</aside><p>대화 본문에 들어 있는 개인정보 삭제나 별도 개인정보 요청도 위 이메일로 접수할 수 있습니다. 이름 표시 변경은 본문 전체의 완전한 익명화를 뜻하지 않습니다.</p><hr><h1>Орчуулагч Ток — Бүртгэл устгах хүсэлт</h1><p>Аппын Тохиргоо → Бүртгэл устгах хүсэлт хэсэгт нууц үгээр баталгаажуулна. Аппыг устгасан эсвэл нэвтрэх боломжгүй бол бүртгэлтэй утасны дугаар болон хүсэлтээ dntprbs@gmail.com хаягт илгээнэ үү. Нууц үг, үнэмлэх бүү илгээгээрэй.</p><p>Бүртгэл, утасны хайлт, мэдэгдлийн төхөөрөмж, үлдсэн эрхийг устгана. Нөгөө хүнд хүрсэн эх болон орчуулсан зурвас хадгалагдаж, нэрийг “Бүртгэлээ устгасан хэрэглэгч” гэж харуулна. Шинээр бүртгүүлсэн ч хуучин чатад нэвтрэхгүй. Зурвас доторх хувийн мэдээллийг устгуулах хүсэлтийг мөн дээрх хаягаар гаргаж болно.</p></html>`;

export function rewardHandler({db,authenticate,enabled=false,localTest=false,iosUnits={},getKeys=googleKeys()}) {
  return async (request,response) => {
    response.setHeader('Cache-Control','no-store');
    const url = new URL(request.url,'http://localhost');
    if (url.pathname === '/invite' && request.method === 'GET') {
      const referral = url.searchParams.get('ref');
      if (!/^[A-F0-9]{16}$/.test(referral ?? '')) {
        response.writeHead(404);response.end();return;
      }
      const play = new URL('https://play.google.com/store/apps/details');
      play.searchParams.set('id','com.tongyeoktalk');
      play.searchParams.set('referrer','tt_ref='+referral);
      const mn = String(request.headers['accept-language'] ?? '').startsWith('mn');
      const ios = /iPhone|iPad|iPod|Macintosh.*Mobile/i.test(request.headers['user-agent'] ?? '');
      const instructions = ios
        ? mn ? 'Аппыг суулгасны дараа энэ холбоос руу буцаж, аппыг нээгээд бүртгүүлнэ үү.' : '통역톡을 설치한 뒤 이 링크를 다시 열고 아래 버튼을 눌러 가입해 주세요.'
        : mn ? 'Аппыг суулгаад бүртгүүлэхэд урилга автоматаар холбогдоно.' : '앱을 설치하고 가입하면 소개자가 자동으로 연결돼요.';
      const installLink = ios ? '' : `<a href="${play.href.replaceAll('&','&amp;')}">${mn?'Google Play-ээс суулгах':'Google Play에서 설치'}</a>`;
      response.setHeader('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
      response.setHeader('Referrer-Policy','no-referrer');
      response.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});
      response.end(`<!doctype html><html lang="${mn?'mn':'ko'}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>통역톡</title><style>body{max-width:28rem;padding:2rem 1.25rem;margin:auto;font:1.1rem/1.6 system-ui;color:#172635} a{display:block;margin:1rem 0;padding:.75rem;background:#0739e4;color:#fff;border-radius:10px;text-align:center}</style><h1>${mn?'Орчуулагч Ток':'통역톡 초대'}</h1><p>${instructions}</p>${installLink}<a href="tongyeoktalk://referral?ref=${referral}">${mn?'Суулгасан аппыг нээх':'설치된 통역톡 열기'}</a></html>`);
      return;
    }
    if(await guestHttp(request,response,{db,authenticate}))return;
    try {
      const accountRequest=url.pathname==='/account-deletion-requests';
      const referralRequest=['/referrals/status','/referrals/register'].includes(url.pathname);
      const adRequest=url.pathname==='/sessions';
      if((accountRequest || referralRequest || adRequest) && request.headers.origin==='https://dntprbs-maker.github.io'){
        response.setHeader('Access-Control-Allow-Origin',request.headers.origin);
        response.setHeader('Vary','Origin');
        response.setHeader('Access-Control-Allow-Headers','Authorization,Content-Type');
        response.setHeader('Access-Control-Allow-Methods','POST,OPTIONS');
        if(request.method==='OPTIONS'){response.writeHead(204);response.end();return;}
      }
      if(url.pathname==='/account-deletion' && request.method==='GET'){
        response.setHeader('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
        response.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});response.end(deletionHelp);return;
      }
      if (url.pathname === '/health' && request.method === 'GET') {
        response.writeHead(200,{'Content-Type':'application/json'});
        response.end(JSON.stringify({ready:enabled,mode:localTest?'local_test':'production'}));return;
      }
      if (url.pathname === '/ssv' && request.method === 'GET') {
        const event = await verifyCallback(url.search.slice(1),getKeys);
        if(!await acknowledgeVerification(db,event))await grantReward(db,event,{localTest});
        response.writeHead(200);response.end('OK');return;
      }
      const testCompletion=localTest&&url.pathname==='/test-completions';
      if ((!testCompletion&&!accountRequest&&!referralRequest&&url.pathname !== '/sessions') || request.method !== 'POST') {response.writeHead(404);response.end();return;}
      if (!accountRequest && !referralRequest && !enabled) throw Error('rewards_not_ready');
      const auth = request.headers.authorization;
      if (!auth?.startsWith('Bearer ')) throw Error('unauthenticated');
      let uid,identity;
      try { identity=await authenticate(auth.slice(7));uid=identity.uid; } catch {throw Error('unauthenticated');}
      let body=request.body;
      if (!body || Buffer.isBuffer(body) || typeof body==='string') {
        let text=body?.toString() ?? '';
        if (!text) for await (const chunk of request) {text+=chunk;if(Buffer.byteLength(text)>2048) throw Error('invalid_request');}
        try {body=JSON.parse(text);}catch{throw Error('invalid_request');}
      }
      if (!body || typeof body!=='object' || Array.isArray(body)) throw Error('invalid_request');
      if(referralRequest){
        const result=url.pathname.endsWith('/register')
          ? await registerReferral(db,uid,body.code)
          : await referralStatus(db,uid);
        response.writeHead(200,{'Content-Type':'application/json'});
        response.end(JSON.stringify(result));return;
      }
      if(accountRequest){
        if(Object.keys(body).some(k=>!['policy','confirmed'].includes(k))||body.policy!==deletionPolicy||body.confirmed!==true)throw Error('invalid_request');
        const result=await requestAccountDeletion(db,identity);
        response.writeHead(200,{'Content-Type':'application/json'});response.end(JSON.stringify(result));return;
      }
      if(testCompletion){
        // LOCAL TEST FIXTURE ONLY. Production never exposes this route and
        // never accepts a client completion callback as proof of a paid ad.
        if(Object.keys(body).some(k=>k!=='sessionId')||!/^[a-f0-9]{64}$/.test(body.sessionId??''))throw Error('invalid_request');
        const session=(await db.doc(`_adRewardSessions/${body.sessionId}`).get()).data();
        if(!session?.testAds||session.uid!==uid)throw Error('invalid_request');
        const result=await grantReward(db,{custom_data:body.sessionId,user_id:uid,ad_unit:session.expectedUnit??TEST_UNIT,reward_amount:'1',reward_item:'Reward',timestamp:String(Date.now()),transaction_id:`local_sdk_${body.sessionId}`},{localTest:true});
        response.writeHead(200,{'Content-Type':'application/json'});response.end(JSON.stringify(result));return;
      }
      if (Object.keys(body).some(k=>!['testAds','platform'].includes(k))) throw Error('invalid_request');
      if (localTest && body.testAds !== true) throw Error('test_rewards_disabled');
      const result = await createSession(db,{uid,testAds:body.testAds,platform:body.platform},{enabled,localTest,iosUnits});
      response.writeHead(200,{'Content-Type':'application/json'});response.end(JSON.stringify(result));
    } catch(error) {
      const known=['unauthenticated','recent_login_required','profile_missing','invalid_request','rewards_not_ready','reward_account_not_enabled','reward_rate_limited','reward_daily_limit','test_rewards_disabled','ios_ads_not_configured','invalid_referral_code','referral_already_registered','referral_role_mismatch','referral_unavailable'];
      const callbackError=url.pathname==='/ssv' && /^(bad_|invalid_signature|unknown_|duplicate_|reward_|transaction_|session_|test_rewards_disabled)/.test(error.message);
      const status=error.message==='unauthenticated'?401:known.includes(error.message)?400:callbackError?400:503;
      response.writeHead(status,{'Content-Type':'application/json'});
      response.end(JSON.stringify({error:known.includes(error.message)?error.message:callbackError?'invalid_callback':'rewards_unavailable'}));
    }
  };
}
