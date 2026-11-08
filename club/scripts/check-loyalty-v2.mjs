import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import readline from 'node:readline/promises';
const rl=readline.createInterface({input:process.stdin,output:process.stdout});
console.log('Ready for QA session JSON on stdin.');
const {session}=JSON.parse(await rl.question(''));rl.close();
const API='https://tmzglobhelevkwerjpom.supabase.co/functions/v1/granero-club';
async function call(action,data={},ok=true){const r=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,...data})});const j=await r.json();assert.equal(r.status,ok?200:400,JSON.stringify(j));return j}
const rand=()=>randomBytes(32).toString('hex'),prefix='QA2-'+Date.now(),wallet=rand();
const d=await call('dashboard',{session}),cfg=d.config;
assert.equal(cfg.test_mode,true);assert.equal(cfg.stamp_enabled,true);assert.equal(cfg.stamp_repeat,true);
await call('members',{page:0,size:25,search:'',test_mode:true},false);
await call('member_detail',{member_id:'invalid',test_mode:true},false);
const settings={session,...cfg,prizes:d.prizes};
await call('settings',{...settings,stamp_goal:1},false);
await call('settings',{...settings,stamp_reward_amount:500,stamp_reward_min:100},false);
await call('settings',settings);
let first,last;
for(let i=1;i<=cfg.stamp_goal+1;i++){
 const t=await call('create',{session,receipt:prefix+'-'+i,amount:Math.max(cfg.min_purchase,cfg.stamp_min_purchase,20000)});
 const spin=await call('spin',{token:t.token,wallet});
 assert.equal(spin.stamp_earned,true);assert.equal(spin.stamp_card.progress,i<=cfg.stamp_goal?i:1);
 assert.equal(spin.stamp_card.goal,cfg.stamp_goal);
 const replay=await call('spin',{token:t.token,wallet});assert.equal(replay.redeem_code,spin.redeem_code);assert.equal(replay.stamp_card.progress,spin.stamp_card.progress);
 if(i===1){first=spin;await call('claim',{token:t.token,wallet,name:prefix+' Cliente',phone:'56900000000',terms:true,marketing:true})}
 if(i===cfg.stamp_goal){assert.ok(spin.stamp_bonus);assert.equal(spin.stamp_bonus.prize_amount,cfg.stamp_reward_amount);assert.ok(spin.stamp_card.completed_at)}
 last=spin;
}
const w=await call('wallet',{wallet});assert.equal(w.cards.length,2);const bonuses=w.tickets.filter(t=>t.reward_source==='loyalty');assert.equal(bonuses.length,1);assert.equal(w.tickets.length,cfg.stamp_goal+2);
const members=await call('members',{session,page:0,size:25,search:prefix,test_mode:true,marketing:true});assert.equal(members.total,1);const m=members.items[0];assert.equal(m.stamps,cfg.stamp_goal+1);assert.ok(m.phone);assert.equal(m.marketing,true);assert.equal(m.token_hash,undefined);
const detail=await call('member_detail',{session,member_id:m.member_id,test_mode:true});assert.equal(detail.cards.length,2);assert.equal(detail.member.token_hash,undefined);
const other=await call('wallet',{wallet:rand()});assert.equal(other.tickets.length,0);assert.equal(other.cards.length,0);
const bonus=bonuses[0];const lookup=await call('lookup',{session,code:bonus.redeem_code});assert.equal(lookup.reward_source,'loyalty');assert.equal(lookup.name,prefix+' Cliente');
await call('redeem',{session,code:bonus.redeem_code,receipt:prefix+'-RETURN',amount:1},false);
await call('redeem',{session,code:first.redeem_code,receipt:prefix+'-SHARED',amount:Math.max(first.prize_min,20000)});
await call('redeem',{session,code:bonus.redeem_code,receipt:prefix+'-SHARED',amount:Math.max(bonus.prize_min,20000)},false);
await call('redeem',{session,code:bonus.redeem_code,receipt:prefix+'-BONUS',amount:Math.max(bonus.prize_min,20000)});
await call('redeem',{session,code:bonus.redeem_code,receipt:prefix+'-BONUS-AGAIN',amount:Math.max(bonus.prize_min,20000)},false);
console.log(JSON.stringify({passed:true,prefix,goal:cfg.stamp_goal,stampCount:m.stamps,bonusRewards:bonuses.length}));
process.exit(0);
