import assert from 'node:assert/strict';import {randomBytes} from 'node:crypto';import readline from 'node:readline/promises';
const rl=readline.createInterface({input:process.stdin,output:process.stdout});console.log('Ready for QA session JSON on stdin.');const {session}=JSON.parse(await rl.question(''));rl.close();
const url='https://tmzglobhelevkwerjpom.supabase.co/functions/v1/granero-club';
async function api(action,data={},ok=true){const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,...data})});const j=await r.json();assert.equal(r.status,ok?200:400,JSON.stringify(j));return j}
const c=await api('config');assert.equal(c.test_mode,true);assert.ok(c.prizes.some(p=>p.id===4&&p.kind==='none'));
const wallet=randomBytes(32).toString('hex'),name='QA6-'+Date.now(),phone='56900000666';
const qr=await api('create',{session,amount:20000});assert.ok(qr.receipt.startsWith('COMPRA-'));
const spin=await api('spin',{token:qr.token,wallet});assert.ok(spin.wheel_prizes.some(p=>p.id===spin.prize_id));assert.equal(spin.allow_same_purchase,true);
if(spin.outcome==='none')assert.equal(spin.redeem_code,null);else {assert.match(spin.redeem_code,/^GF-[A-F0-9]{12}$/);await api('redeem',{session,code:spin.redeem_code,receipt:qr.receipt,amount:20000})}
await api('claim',{token:qr.token,wallet,name,phone,pin:'246810',terms:true},false);
await api('claim',{token:qr.token,wallet,name,phone,pin:'2468',terms:true});
const login=await api('customer_login',{phone,pin:'2468'});assert.equal(login.accounts.length,1);const w=await api('wallet',{wallet:login.accounts[0].token});assert.equal(w.member.name,name);
console.log(JSON.stringify({passed:true,name,receipt:qr.receipt,fourDigitPin:true,automaticCodes:true,outcome:spin.outcome}));process.exit(0);
