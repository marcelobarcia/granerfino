import fs from 'node:fs';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import assert from 'node:assert/strict';
const storage=new Map();
const context=vm.createContext({
 console,crypto:webcrypto,URLSearchParams,URL,Date,Blob,FormData,
 location:{origin:'https://example.test',pathname:'/',search:'',hash:''},
 history:{replaceState(){}},localStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},sessionStorage:{getItem:()=>null},
 document:{addEventListener(){},head:{append(){}},createElement:()=>({}),querySelector:()=>null},
 window:{},matchMedia:()=>({matches:false}),setTimeout,clearTimeout,
});
const html=fs.readFileSync('dist/index.html','utf8');
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
vm.runInContext(fs.readFileSync('dist/club-v2.js','utf8').replace(/\ninit\(\);\s*$/,''),context);
vm.runInContext(`dash={config:{test_mode:true,min_purchase:3000,validity_days:14,daily_budget:10000,stamp_enabled:true,stamp_goal:5,stamp_min_purchase:3000,stamp_repeat:true,stamp_reward_kind:'product',stamp_reward_title:'Mix <especial>',stamp_reward_amount:0,stamp_reward_min:10000,stamp_reward_days:30},prizes:[{id:1,amount:300,min_purchase:7000,weight:60},{id:2,amount:500,min_purchase:10000,weight:30},{id:3,amount:1000,min_purchase:15000,weight:10}],tickets:[]}; cfg=dash.config; session='test-session';`,context);
vm.runInContext(fs.readFileSync('dist/customer-access.js','utf8').replace(/\ninit\(\);\s*$/,''),context);
const settings=vm.runInContext('renderSettings()',context);
for(const field of ['stamp_enabled','stamp_goal','stamp_min_purchase','stamp_repeat','stamp_reward_kind','stamp_reward_title','stamp_reward_amount','stamp_reward_min','stamp_reward_days'])assert.ok(settings.includes('name="'+field+'"'),field);
assert.ok(settings.includes('Mix &lt;especial&gt;'));
vm.runInContext(`memberData={member:{name:'<script>test</script>'},cards:[{test_mode:true,progress:5,goal:5,completed_at:'2026-11-08',repeat_card:true,reward_kind:'product',reward_title:'Mix especial',reward_min:10000,reward_days:30}],tickets:[{prize_kind:'product',reward_source:'loyalty',prize_title:'Mix especial',prize_amount:0,prize_min:10000,prize_expires_at:'2030-11-01',redeem_code:'GC-TEST',test_mode:true}]};`,context);
const wallet=vm.runInContext('renderWallet()',context);
assert.ok(wallet.includes('¡Tarjeta completa!'));assert.ok(wallet.includes('&lt;script&gt;'));assert.ok(!wallet.includes('$0 de descuento'));assert.ok(wallet.includes('Mix especial'));
vm.runInContext(`lookup={...memberData.tickets[0],name:'Cliente de prueba'};`,context);
const redeem=vm.runInContext('renderRedeem()',context);assert.ok(!redeem.includes('Confirmar canje de $0'));assert.ok(redeem.includes('Confirmar canje'));
console.log('Frontend: configuration fields, product rewards, completed card and HTML escaping passed.');

const access=vm.runInContext("view=\"customer-login\";renderAccess()",context);assert.ok(access.includes("customer-login-form"));assert.ok(access.includes("name=\"pin\""));
const register=vm.runInContext("renderRegister()",context);assert.ok(register.includes("name=\"pin_confirm\""));
const help=vm.runInContext('renderWhatsAppHelp()',context);
const helpLinks=[...help.matchAll(/href="([^"]+)"/g)].map(x=>new URL(x[1]));
assert.equal(helpLinks.length,2);
assert.deepEqual(helpLinks.map(x=>x.hostname),['api.whatsapp.com','web.whatsapp.com']);
for(const link of helpLinks){assert.equal(link.protocol,'https:');assert.equal(link.searchParams.get('phone'),'56934263907');assert.ok(link.searchParams.get('text').includes('recuperar el acceso'))}
assert.equal((help.match(/target="_top"/g)||[]).length,2);assert.ok(!help.includes('target="_blank"'));assert.ok(help.includes('data-action="copy-support-number"'));
console.log('WhatsApp help links and copy fallback passed.');
