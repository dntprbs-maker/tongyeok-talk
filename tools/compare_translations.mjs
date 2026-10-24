import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {config,translate} from './translation_provider.mjs';
const live=process.argv.includes('--live');
if (!live) {console.log(JSON.stringify({mode:'dry-run',models:config.models,cases:6,calls:18,keyNeeded:'OPENROUTER_API_KEY or TONGYEOK_OPENROUTER_KEY_FILE (outside repo)'}));process.exit(0);}
const apiKey=process.env.OPENROUTER_API_KEY || (process.env.TONGYEOK_OPENROUTER_KEY_FILE?readFileSync(process.env.TONGYEOK_OPENROUTER_KEY_FILE,'utf8').trim():null);
if(!apiKey) throw new Error('openrouter_key_missing');
const cases=JSON.parse(readFileSync(new URL('./translation_cases.json',import.meta.url),'utf8'));
const dir=resolve('artifacts/translation-comparison',new Date().toISOString().replaceAll(':','-'));
mkdirSync(dir,{recursive:true});
const rows=[];
// Intentionally sequential, bounded to 18 calls; no automatic paid retry/fallback.
comparison: for(const sample of cases) for(const model of config.models){
  const row={...sample,model:model.id,testedAt:new Date().toISOString(),review:{status:'미검증',naturalness:null,accuracy:null,correction:null}};
  try{Object.assign(row,await translate({model:model.id,...sample},{apiKey}));row.status='received';}
  catch(error){row.status='failed';row.error=error.message;}
  rows.push(row);writeFileSync(resolve(dir,'results.json'),JSON.stringify(rows,null,2));
  console.log(JSON.stringify({case:sample.id,model:model.id,status:row.status,costUsd:row.costUsd??null}));
  if(row.error==='openrouter_http_401'||row.error==='openrouter_http_402') {console.log('Stopped: credentials or credit need attention.');break comparison;}
}
const safe=value=>String(value??'').replaceAll('|','\\|').replaceAll('\n','<br>');
writeFileSync(resolve(dir,'REVIEW.md'),'# 통역톡 번역 비교 · '+new Date().toISOString()+'\n\n실제 AI 응답 기록. 몽골어 사용자 검수 전이며 수신 성공은 품질 통과를 뜻하지 않음.\n\n|시험|방향|모델|원문|번역문|결과|시간(ms)|비용(USD)|검수 의견|\n|---|---|---|---|---|---|---:|---:|---|\n'+rows.map(r=>[r.id,`${r.source}→${r.target}`,r.model,r.text,r.translation,r.error??r.status,r.latencyMs,r.costUsd,'미검증'].map(safe).join('|')).map(r=>'|'+r+'|').join('\n'));
console.log(JSON.stringify({results:dir,completed:rows.length,totalCostUsd:rows.every(r=>r.costUsd!=null)?rows.reduce((sum,r)=>sum+r.costUsd,0):null}));
