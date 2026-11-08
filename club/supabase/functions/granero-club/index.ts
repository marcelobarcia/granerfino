import { createClient } from 'npm:@supabase/supabase-js@2.99.1';

const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type, authorization, apikey','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Content-Type':'application/json'};
const hex=(a:ArrayBuffer)=>Array.from(new Uint8Array(a)).map(x=>x.toString(16).padStart(2,'0')).join('');
const hash=async(s:string)=>hex(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)));
const token=()=>hex(crypto.getRandomValues(new Uint8Array(32)).buffer);
const passwordHash=async(password:string,salt:string)=>{
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(password),'PBKDF2',false,['deriveBits']);
 return hex(await crypto.subtle.deriveBits({name:'PBKDF2',salt:new TextEncoder().encode(salt),iterations:210000,hash:'SHA-256'},key,256));
};
function check(r:any){if(r.error)throw new Error(r.error.message);return r.data;}
function text(v:unknown,max=100){if(typeof v!=='string'||!v.trim()||v.length>max)throw new Error('Revisá los datos ingresados');return v.trim();}
function capability(v:unknown){const s=text(v,64);if(!/^[a-f0-9]{64}$/.test(s))throw new Error('Enlace no válido');return s;}
function amount(v:unknown){if(!Number.isInteger(v)||Number(v)<1||Number(v)>10000000)throw new Error('Ingresá un monto válido');return Number(v);}
const configFields='test_mode,min_purchase,validity_days,daily_budget,stamp_enabled,stamp_goal,stamp_min_purchase,stamp_repeat,stamp_reward_kind,stamp_reward_title,stamp_reward_amount,stamp_reward_min,stamp_reward_days';
const cardFields='id,cycle,test_mode,progress,goal,min_purchase,repeat_card,reward_kind,reward_title,reward_amount,reward_min,reward_days,created_at,completed_at';
const prizeFields='prize_title,prize_amount,prize_min,prize_expires_at,redeem_code,redeemed_at,test_mode,created_at,revoked,allow_same_purchase';
async function walletContent(wh:string){
 const [t,c,b]=await Promise.all([
  db.from('gf_tickets').select(prizeFields).eq('wallet_hash',wh).eq('outcome','prize').not('spun_at','is',null).order('created_at',{ascending:false}).limit(500),
  db.from('gf_cards').select(cardFields).eq('wallet_hash',wh).order('cycle',{ascending:false}).limit(100),
  db.from('gf_bonus_rewards').select(prizeFields+',prize_kind').eq('wallet_hash',wh).order('created_at',{ascending:false}).limit(500)
 ]);
 return {cards:check(c),tickets:[...check(t).map((x:any)=>({...x,prize_kind:'discount',reward_source:'roulette'})),...check(b).map((x:any)=>({...x,reward_source:'loyalty'}))].sort((a:any,b:any)=>b.created_at.localeCompare(a.created_at))};
}
const safeTicket=(t:any)=>{const {token_hash,wallet_hash,...rest}=t;return rest;};
async function rpc(name:string,args:any){return check(await db.rpc(name,args));}
async function admin(s:unknown){const h=await hash(capability(s));const row=check(await db.from('gf_sessions').select('expires_at').eq('token_hash',h).maybeSingle());if(!row||new Date(row.expires_at)<new Date())throw new Error('Ingresá de nuevo a Caja');}
function customerPin(v:unknown,legacy=false){if(typeof v!=='string'||!(legacy?/^\d{4}(?:\d{2})?$/:/^\d{4}$/).test(v))throw new Error('El PIN debe tener 4 números');return v;}
function customerPhone(v:unknown){const p=text(v,20).replace(/[\s()+-]/g,'');if(!/^569\d{8}$/.test(p))throw new Error('Ingresá un celular chileno: +56 9 y ocho dígitos');return p;}
async function resolveWallet(v:unknown){
 const h=await hash(capability(v));const s=check(await db.from('gf_customer_sessions').select('wallet_hash,expires_at').eq('token_hash',h).maybeSingle());
 if(s){if(new Date(s.expires_at)<new Date())throw new Error('Ingresá de nuevo con tu celular y PIN');return s.wallet_hash;}
 const w=check(await db.from('gf_wallets').select('legacy_access_enabled').eq('token_hash',h).maybeSingle());
 if(w&&!w.legacy_access_enabled)throw new Error('Este acceso fue reemplazado. Ingresá con tu celular y PIN');
 return h;
}
async function customerSession(wh:string){const t=token();check(await db.from('gf_customer_sessions').insert({token_hash:await hash(t),wallet_hash:wh,expires_at:new Date(Date.now()+180*86400000).toISOString()}));return t;}

Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return new Response(JSON.stringify({error:'Método no permitido'}),{status:405,headers:cors});
 try{
  if(Number(req.headers.get('content-length')||0)>12000)throw new Error('Solicitud demasiado grande');
  const raw=await req.text();if(raw.length>12000)throw new Error('Solicitud demasiado grande');
  const b=JSON.parse(raw), action=b.action;
  const ip=req.headers.get('cf-connecting-ip')||req.headers.get('x-forwarded-for')?.split(',')[0]||'unknown';
  if(['customer_login','recover_finish'].includes(action)&&!await rpc('gf_rate',{p_key:'customer-ip:'+await hash(ip),p_limit:20,p_seconds:900}))throw new Error('Demasiados intentos. Esperá 15 minutos');
  if(action==='customer_login'){
   const phone=customerPhone(b.phone),pin=customerPin(b.pin,true);
   if(!await rpc('gf_rate',{p_key:'customer-phone:'+await hash(phone),p_limit:5,p_seconds:900}))throw new Error('Demasiados intentos. Esperá 15 minutos o pedí ayuda en la tienda');
   const rows=check(await db.from('gf_wallets').select('token_hash,name,created_at,customer_pin_hash,customer_pin_salt').eq('phone',phone).not('customer_pin_hash','is',null).order('created_at').limit(20));
   const matches=[];
   for(const w of rows)if(await passwordHash(pin,w.customer_pin_salt)===w.customer_pin_hash)matches.push({name:w.name,created_at:w.created_at,token:await customerSession(w.token_hash)});
   if(!matches.length)throw new Error('No pudimos ingresar con esos datos. Revisá tu celular y PIN o pedí ayuda en la tienda');
   return new Response(JSON.stringify({accounts:matches}),{headers:cors});
  }
  if(action==='customer_pin'){
   const wh=await resolveWallet(b.wallet),pin=customerPin(b.pin),salt=token();
   const rows=check(await db.from('gf_wallets').update({customer_pin_hash:await passwordHash(pin,salt),customer_pin_salt:salt}).eq('token_hash',wh).select('member_id'));
   if(!rows.length)throw new Error('Primero guardá tu premio para ser miembro del club');
   return new Response('{"ok":true}',{headers:cors});
  }
  if(action==='customer_logout'){
   check(await db.from('gf_customer_sessions').delete().eq('token_hash',await hash(capability(b.wallet))));
   return new Response('{"ok":true}',{headers:cors});
  }
  if(action==='recover_finish'){
   const pin=customerPin(b.pin),salt=token(),s=token();
   await rpc('gf_finish_recovery',{p_token:await hash(capability(b.recovery)),p_pin:await passwordHash(pin,salt),p_salt:salt,p_session:await hash(s)});
   return new Response(JSON.stringify({token:s}),{headers:cors});
  }
  if(['login','setup'].includes(action)&&!await rpc('gf_rate',{p_key:'login:'+await hash(ip),p_limit:12,p_seconds:900}))throw new Error('Demasiados intentos. Esperá 15 minutos');
  if(action==='config'){
   const c=check(await db.from('gf_config').select(configFields).eq('id',true).single());
   const prizes=check(await db.from('gf_prizes').select('id,title,amount,min_purchase,weight,kind').eq('active',true).order('id'));
   return new Response(JSON.stringify({...c,prizes}),{headers:cors});
  }
  if(action==='setup'){
   const setup=await hash(capability(b.setup)),password=text(b.password,128);if(password.length<12)throw new Error('Usá una contraseña de al menos 12 caracteres');
   const salt=token();const ok=await rpc('gf_setup',{p_setup:setup,p_hash:await passwordHash(password,salt),p_salt:salt});
   if(!ok)throw new Error('Este enlace de activación ya se usó o no es válido');
   return new Response(JSON.stringify({ok:true}),{headers:cors});
  }
  if(action==='login'){
   if(String(b.username||'').trim().toLowerCase()!=='admin')throw new Error('Usuario o contraseña incorrectos');
   const c=check(await db.from('gf_config').select('password_hash,password_salt').eq('id',true).single());
   if(!c.password_hash||await passwordHash(text(b.password,128),c.password_salt)!==c.password_hash)throw new Error('Usuario o contraseña incorrectos');
   const session=token();check(await db.from('gf_sessions').insert({token_hash:await hash(session),expires_at:new Date(Date.now()+12*3600000).toISOString()}));
   return new Response(JSON.stringify({session}),{headers:cors});
  }
  if(action==='logout'){await admin(b.session);check(await db.from('gf_sessions').delete().eq('token_hash',await hash(b.session)));return new Response('{"ok":true}',{headers:cors});}
  if(['dashboard','create','lookup','redeem','settings','revoke','members','member_detail','recovery_link','assisted_create','assisted_purchase','pending_prizes'].includes(action))await admin(b.session);
  if(action==='pending_prizes'){
   const page=Number(b.page??0),size=Number(b.size??25);if(typeof b.test_mode!=='boolean'||!Number.isInteger(page)||page<0||!Number.isInteger(size)||size<1||size>100)throw new Error('Página no válida');
   return new Response(JSON.stringify(await rpc('gf_pending_prizes',{p_mode:b.test_mode,p_search:typeof b.search==='string'?b.search.trim().slice(0,100):'',p_page:page,p_size:size})),{headers:cors});
  }
  if(action==='assisted_create'){
   const name=text(b.name,60),phone=typeof b.phone==='string'?b.phone.replace(/[\s()+-]/g,''):'';
   if(phone&&!/^56[2-9]\d{8}$/.test(phone))throw new Error('Ingresá un teléfono chileno válido o dejalo vacío');
   if(b.consent!==true)throw new Error('Confirmá que el cliente acepta registrarse en el club');
   const c=check(await db.from('gf_config').select('test_mode').eq('id',true).single());
   const w=check(await db.from('gf_wallets').insert({token_hash:await hash(token()),name,phone,marketing:b.marketing===true,assisted:true,registration_test_mode:c.test_mode}).select('member_id,member_code,name,phone').single());
   return new Response(JSON.stringify(w),{headers:cors});
  }
  if(action==='assisted_purchase'){
   const id=text(b.member_id,36);if(!/^[a-f0-9-]{36}$/i.test(id))throw new Error('Miembro no válido');
   const w=check(await db.from('gf_wallets').select('token_hash,name,member_code').eq('member_id',id).maybeSingle());
   if(!w)throw new Error('Miembro no encontrado');
   const result=await rpc('gf_assisted_purchase',{p_wallet:w.token_hash,p_receipt:typeof b.receipt==='string'&&b.receipt.trim()?text(b.receipt,60):'COMPRA-'+token().slice(0,12).toUpperCase(),p_amount:amount(b.amount),p_token:await hash(token()),p_random:crypto.getRandomValues(new Uint32Array(1))[0]/4294967296,p_code:'GF-'+token().slice(0,12).toUpperCase()});
   return new Response(JSON.stringify({...result,name:w.name,member_code:w.member_code}),{headers:cors});
  }
  if(action==='recovery_link'){
   if(b.verified!==true)throw new Error('Verificá al cliente y el control del celular registrado antes de generar el enlace');
   const id=text(b.member_id,36);if(!/^[a-f0-9-]{36}$/i.test(id))throw new Error('Miembro no válido');
   const w=check(await db.from('gf_wallets').select('token_hash,phone,name').eq('member_id',id).maybeSingle());
   if(!w)throw new Error('Miembro no encontrado');if(!/^569\d{8}$/.test(w.phone))throw new Error('Este miembro no tiene celular registrado. Su cuenta se gestiona desde Caja');const t=token();await rpc('gf_make_recovery',{p_wallet:w.token_hash,p_token:await hash(t)});
   return new Response(JSON.stringify({recovery:t,phone:w.phone,name:w.name,expires_minutes:15}),{headers:cors});
  }
  if(action==='dashboard'){
   const config=check(await db.from('gf_config').select(configFields).eq('id',true).single());
   const prizes=check(await db.from('gf_prizes').select('*').order('id'));
   const tickets=check(await db.from('gf_tickets').select('receipt,purchase_amount,test_mode,created_at,spun_at,prize_title,prize_amount,redeemed_at,revoked').order('created_at',{ascending:false}).limit(100));
   return new Response(JSON.stringify({config,prizes,tickets}),{headers:cors});
  }
  if(action==='settings'){
   const min=amount(b.min_purchase),days=amount(b.validity_days),budget=amount(b.daily_budget);
   if(days>90||typeof b.test_mode!=='boolean')throw new Error('Configuración no válida');
   if(!Array.isArray(b.prizes)||![3,4].includes(b.prizes.length))throw new Error('Revisá los resultados de la ruleta');
   for(const p of b.prizes){
    if(![1,2,3,4].includes(p.id)||!Number.isInteger(p.weight)||p.weight<0||p.weight>10000)throw new Error('Revisá las probabilidades');
    if(p.id===4){p.amount=0;p.min_purchase=0;p.title='Sigue participando';}
    else if(amount(p.min_purchase)<amount(p.amount))throw new Error('El mínimo debe cubrir el descuento');
   }
   if(new Set(b.prizes.map((p:any)=>p.id)).size!==b.prizes.length||!b.prizes.some((p:any)=>p.weight>0))throw new Error('Debe haber al menos un resultado con probabilidad positiva');
   if(!b.prizes.some((p:any)=>p.id!==4&&p.weight>0&&p.min_purchase<=min&&p.amount<=budget))throw new Error('El mínimo para girar debe habilitar al menos un premio. Bajá el mínimo de un premio o aumentá el mínimo del giro');
   const current=check(await db.from('gf_config').select(configFields).eq('id',true).single());
   const config={...current,test_mode:b.test_mode,min_purchase:min,validity_days:days,daily_budget:budget};
   for(const key of Object.keys(current).filter(k=>k.startsWith('stamp_')))if(b[key]!==undefined)config[key]=b[key];
   if(typeof config.stamp_enabled!=='boolean'||typeof config.stamp_repeat!=='boolean'||!Number.isInteger(config.stamp_goal)||config.stamp_goal<2||config.stamp_goal>20)throw new Error('La tarjeta debe tener entre 2 y 20 sellos');
   amount(config.stamp_min_purchase);amount(config.stamp_reward_min);
   if(!['discount','product'].includes(config.stamp_reward_kind)||!Number.isInteger(config.stamp_reward_days)||config.stamp_reward_days<1||config.stamp_reward_days>365)throw new Error('Revisá el tipo y la vigencia del premio especial');
   config.stamp_reward_title=text(config.stamp_reward_title,100);
   if(config.stamp_reward_kind==='discount'){
    amount(config.stamp_reward_amount);if(config.stamp_reward_min<config.stamp_reward_amount)throw new Error('El mínimo del premio especial debe cubrir su descuento');
   }else config.stamp_reward_amount=0;
   await rpc('gf_settings',{p_config:config,p_prizes:b.prizes.map((p:any)=>({...p,title:p.id===4?'Sigue participando':`$${p.amount.toLocaleString('es-CL')} de descuento`}))});
   return new Response('{"ok":true}',{headers:cors});
  }
  if(action==='create'){
   const receipt=typeof b.receipt==='string'&&b.receipt.trim()?text(b.receipt,60):'COMPRA-'+token().slice(0,12).toUpperCase(),purchase=amount(b.amount),c=check(await db.from('gf_config').select('*').eq('id',true).single());
   if(purchase<c.min_purchase)throw new Error('La compra no alcanza el mínimo para girar');
   const t=token();const r=await db.from('gf_tickets').insert({token_hash:await hash(t),receipt,purchase_amount:purchase,test_mode:c.test_mode,expires_at:new Date(Date.now()+7*86400000).toISOString()});
   if(r.error?.code==='23505')throw new Error('Ese comprobante ya tiene un QR. No se generó otro');check(r);
   return new Response(JSON.stringify({token:t,test_mode:c.test_mode,receipt}),{headers:cors});
  }
  if(action==='revoke'){
   const r=check(await db.from('gf_tickets').update({revoked:true}).eq('receipt',text(b.receipt,60)).eq('test_mode',Boolean(b.test_mode)).is('spun_at',null).select('receipt'));
   if(!r.length)throw new Error('Solo podés anular un QR que todavía no se usó');return new Response('{"ok":true}',{headers:cors});
  }
  if(action==='ticket'){
   const t=check(await db.from('gf_tickets').select('*').eq('token_hash',await hash(capability(b.token))).maybeSingle());
   if(!t||t.revoked)throw new Error('Este QR no está disponible');
   const same=b.wallet&&t.wallet_hash===await resolveWallet(b.wallet);
   if(t.spun_at&&!same)throw new Error('Este QR ya fue utilizado');
   return new Response(JSON.stringify({...safeTicket(t),...await rpc('gf_stamp_info',{p_token:await hash(b.token)})}),{headers:cors});
  }
  if(action==='spin'){
   const random=crypto.getRandomValues(new Uint32Array(1))[0]/4294967296;
   const code='GF-'+token().slice(0,12).toUpperCase();
   const wh=await resolveWallet(b.wallet);
   const result=await rpc('gf_spin',{p_token:await hash(capability(b.token)),p_wallet:wh,p_random:random,p_code:code});
   const registered=check(await db.from('gf_wallets').select('member_id').eq('token_hash',wh).maybeSingle());
   return new Response(JSON.stringify({...result,registered:!!registered}),{headers:cors});
  }
  if(action==='claim'){
   const th=await hash(capability(b.token)),wh=await resolveWallet(b.wallet);
   const t=check(await db.from('gf_tickets').select('wallet_hash,spun_at,revoked').eq('token_hash',th).single());
   if(!t.spun_at||t.revoked||t.wallet_hash!==wh)throw new Error('Primero girá la ruleta con tu QR');
   const name=text(b.name,60),phone=customerPhone(b.phone);
   if(b.terms!==true)throw new Error('Aceptá las condiciones para guardar el premio');
   const existing=check(await db.from('gf_wallets').select('member_id').eq('token_hash',wh).maybeSingle());
   const extra:any={};if(b.pin!==undefined||!existing){const pin=customerPin(b.pin),salt=token();extra.customer_pin_hash=await passwordHash(pin,salt);extra.customer_pin_salt=salt;}
   check(await db.from('gf_wallets').upsert({token_hash:wh,name,phone,marketing:b.marketing===true,terms_version:'v1',registration_test_mode:t.test_mode,...extra}));
   return new Response('{"ok":true}',{headers:cors});
  }
  if(action==='wallet'){
   const wh=await resolveWallet(b.wallet);const row=check(await db.from('gf_wallets').select('name,phone,member_code,customer_pin_hash').eq('token_hash',wh).maybeSingle());
   const member=row?{name:row.name,phone:row.phone,member_code:row.member_code,pin_enabled:!!row.customer_pin_hash}:null;
   const content=member?await walletContent(wh):{tickets:[],cards:[]};
   return new Response(JSON.stringify({member,...content}),{headers:cors});
  }
  if(action==='members'){
   const page=Number(b.page??0),size=Number(b.size??25);if(!Number.isInteger(page)||page<0||!Number.isInteger(size)||size<1||size>500||typeof b.test_mode!=='boolean')throw new Error('Página no válida');
   const search=typeof b.search==='string'?b.search.trim().slice(0,100):'';
   return new Response(JSON.stringify(await rpc('gf_members',{p_search:search,p_mode:b.test_mode,p_marketing:b.marketing===true,p_page:page,p_size:size})),{headers:cors});
  }
  if(action==='member_detail'){
   const id=text(b.member_id,36);if(!/^[a-f0-9-]{36}$/i.test(id)||typeof b.test_mode!=='boolean')throw new Error('Miembro no válido');
   const w=check(await db.from('gf_wallets').select('token_hash,member_id,member_code,assisted,name,phone,marketing,created_at').eq('member_id',id).maybeSingle());
   if(!w)throw new Error('Miembro no encontrado');
   const content=await walletContent(w.token_hash);const {token_hash,...member}=w;
   return new Response(JSON.stringify({member,tickets:content.tickets.filter((t:any)=>t.test_mode===b.test_mode),cards:content.cards.filter((c:any)=>c.test_mode===b.test_mode)}),{headers:cors});
  }
  if(action==='lookup'){
   const code=text(b.code,30).toUpperCase(),isBonus=code.startsWith('GC-');const t=check(await db.from(isBonus?'gf_bonus_rewards':'gf_tickets').select('*').eq('redeem_code',code).maybeSingle());
   if(!t)throw new Error('No encontramos ese premio');const w=t.wallet_hash?check(await db.from('gf_wallets').select('name').eq('token_hash',t.wallet_hash).maybeSingle()):null;
   return new Response(JSON.stringify({...safeTicket(t),prize_kind:isBonus?t.prize_kind:'discount',reward_source:isBonus?'loyalty':'roulette',name:w?.name||null}),{headers:cors});
  }
  if(action==='redeem'){
   const code=text(b.code,30).toUpperCase();return new Response(JSON.stringify(await rpc(code.startsWith('GC-')?'gf_bonus_redeem':'gf_redeem',{p_code:code,p_receipt:text(b.receipt,60),p_amount:amount(b.amount)})),{headers:cors});
  }
  throw new Error('Acción no disponible');
 }catch(e){const msg=e instanceof Error?e.message:'No pudimos completar la operación';return new Response(JSON.stringify({error:msg.includes('duplicate key')?'Ese comprobante ya se usó para un canje':msg}),{status:400,headers:cors});}
});
