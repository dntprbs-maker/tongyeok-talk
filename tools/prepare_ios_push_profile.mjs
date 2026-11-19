import {sign} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

const bundleIdentifier='com.tongyeoktalk';
export function signingCertificates(certificates, existingContents) {
  const existing=new Set(existingContents.map(x=>x.replace(/\s/g,'')));
  const matches=certificates.filter(x=>existing.has((x.attributes.certificateContent??'').replace(/\s/g,'')));
  if(matches.length!==existing.size || matches.length===0)throw Error('existing_signing_certificate_not_found');
  return matches.map(x=>({type:'certificates',id:x.id}));
}
export function assertPushBundle(bundle,capabilities) {
  if(bundle?.attributes?.identifier!==bundleIdentifier)throw Error('unexpected_bundle');
  if(!capabilities.some(x=>x.attributes.capabilityType==='PUSH_NOTIFICATIONS'))throw Error('apple_push_not_enabled');
}

async function main() {
  const e=process.env;
  if(!e.ASC_KEY || !e.ASC_KEY_ID || !e.ASC_ISSUER_ID || !e.IOS_EXISTING_PROFILE_PLIST || !e.IOS_PUSH_PROFILE_OUTPUT)throw Error('push_signing_environment_missing');
  const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  async function apple(path,query={},data) {
    const now=Math.floor(Date.now()/1000);
    const input=enc({alg:'ES256',kid:e.ASC_KEY_ID,typ:'JWT'})+'.'+enc({iss:e.ASC_ISSUER_ID,iat:now,exp:now+300,aud:'appstoreconnect-v1'});
    const signature=sign('sha256',Buffer.from(input),{key:e.ASC_KEY,dsaEncoding:'ieee-p1363'}).toString('base64url');
    const url=new URL(path,'https://api.appstoreconnect.apple.com');
    if(url.origin!=='https://api.appstoreconnect.apple.com')throw Error('unexpected_apple_origin');
    url.search=new URLSearchParams(query);
    const r=await fetch(url,{method:data?'POST':'GET',headers:{Authorization:`Bearer ${input}.${signature}`,'Content-Type':'application/json'},...(data?{body:JSON.stringify({data})}:{})});
    if(!r.ok)throw Error(`apple_profile_request_${r.status}`);
    return (await r.json()).data;
  }
  const bundles=await apple('/v1/bundleIds',{'filter[identifier]':bundleIdentifier});
  if(bundles.length!==1)throw Error('bundle_not_unique');
  const bundle=bundles[0];
  assertPushBundle(bundle,await apple(`/v1/bundleIds/${bundle.id}/bundleIdCapabilities`));
  const encoded=JSON.parse(execFileSync('python3',['-c',"import sys,plistlib,base64,json; p=plistlib.load(open(sys.argv[1],'rb')); print(json.dumps([base64.b64encode(x).decode() for x in p['DeveloperCertificates']]))",e.IOS_EXISTING_PROFILE_PLIST],{encoding:'utf8'}));
  const certs=signingCertificates(await apple('/v1/certificates',{limit:'200'}),encoded);
  const name='Tongyeok Talk Push TestFlight 20261119';
  const profiles=await apple(`/v1/bundleIds/${bundle.id}/profiles`,{limit:'200'});
  let profile=profiles.find(x=>x.attributes.name===name && x.attributes.profileState==='ACTIVE');
  if(profile) {
    const attached=await apple(`/v1/profiles/${profile.id}/certificates`);
    if(!certs.every(x=>attached.some(y=>y.id===x.id)))throw Error('existing_push_profile_certificate_mismatch');
    profile=(await apple(`/v1/profiles/${profile.id}`));
  } else {
    if(profiles.some(x=>x.attributes.name===name))throw Error('previous_push_profile_needs_review');
    profile=await apple('/v1/profiles',{}, {type:'profiles',attributes:{name,profileType:'IOS_APP_STORE'},relationships:{bundleId:{data:{type:'bundleIds',id:bundle.id}},certificates:{data:certs}}});
  }
  if(!profile.attributes.profileContent)throw Error('profile_content_missing');
  writeFileSync(e.IOS_PUSH_PROFILE_OUTPUT,Buffer.from(profile.attributes.profileContent,'base64'),{mode:0o600});
  console.log('Prepared app-specific push profile with the existing signing certificate');
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href)await main();
