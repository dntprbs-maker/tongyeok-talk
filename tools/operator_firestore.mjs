import {Firestore} from '@google-cloud/firestore';
import {GoogleAuth,OAuth2Client} from 'google-auth-library';
export const projectId='tongyeok-talk-lab-20261024';
export async function operatorFirestore(){
  if(process.env.TONGYEOK_PROJECT!==projectId)throw new Error('isolated_project_guard');
  const credential=await (await import(process.env.TONGYEOK_OPERATOR_AUTH_MODULE)).default();
  const client=new OAuth2Client();
  client.refreshHandler=async()=>{const token=await credential.getAccessToken();return {access_token:token.access_token,expiry_date:Date.now()+240000};};
  return new Firestore({projectId,auth:new GoogleAuth({authClient:client,projectId})});
}
