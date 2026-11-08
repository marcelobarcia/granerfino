let cashierMember=null,cashierOperation=null,cashierRunning=false;
function cashierReset(){cashierMember=null;cashierOperation=null;selectedPrize=null;lookup=null;ticket=null;memberData=null;memberSearch='';memberPage=0;activeWheelPrizes=null;$('#overlay').innerHTML='';adminTab='members';loadMembers()}
document.addEventListener('click',async e=>{const b=e.target.closest('[data-action]');if(!b)return;
 if(b.dataset.action==='assisted-purchase'){cashierMember=b.dataset.id;cashierOperation=random();modal(`<div class="center"><span class="tag">COMPRA VALIDADA EN CAJA</span><h2>Un giro y un sello</h2><p>El premio se canjea en este momento. Aplicá el descuento en Odoo.</p><p>Cargando cliente…</p></div>`);try{const d=await api('member_detail',{session,member_id:cashierMember,test_mode:dash.config.test_mode});if(cashierMember===d.member.member_id){modal(`<div class="wheel-stage"><header><span class="tag">COMPRA VALIDADA EN CAJA</span><h2>${esc(d.member.name)}</h2><p>Un giro · Un sello · Canje inmediato</p></header><main>${wheel()}</main><footer><button class="btn gold full" data-action="cashier-spin">Girar para ${esc(d.member.name)}</button><button class="back" data-action="cashier-next">Cambiar cliente</button><div id="cashier-error"></div></footer></div>`)}}catch(e){toast(e.message)}}
 if(b.dataset.action==='cashier-next'&&!cashierRunning)cashierReset();
 if(b.dataset.action==='cashier-spin'&&cashierMember&&!cashierRunning){cashierRunning=true;b.disabled=true;window.GraneroAudio?.unlock();try{const r=await api('cashier_visit',{session,member_id:cashierMember,operation:cashierOperation});await animateAssistedWheel(r);modal(`<div class="center"><span class="tag">${r.test_mode?'PRUEBA · SIN DESCUENTO REAL':'CANJE REGISTRADO'}</span><h2>${esc(r.name)}</h2><div class="prize-banner"><div class="value">${r.outcome==='none'?'Sigue participando':money(r.prize_amount)}</div><strong>${r.outcome==='none'?'Esta compra también suma su sello':'Aplicar ahora en Odoo'}</strong></div>${stampResult(r)}${r.stamp_bonus?'<p class="notice">Premio por sellos: '+esc(r.stamp_bonus.prize_title)+' · Entregar ahora</p>':''}<button class="btn full" data-action="cashier-next">Siguiente cliente →</button></div>`);cashierMember=null;cashierOperation=null;}catch(e){toast(e.message);b.disabled=false}finally{cashierRunning=false}}
});
const cashierStyle=document.createElement('style');cashierStyle.textContent=`
#overlay .modal-bg:has(.wheel-stage){padding:0;background:var(--cream);backdrop-filter:none}
#overlay .modal:has(.wheel-stage){width:100vw;max-width:none;height:100dvh;max-height:none;border-radius:0;padding:max(12px,env(safe-area-inset-top)) max(16px,env(safe-area-inset-right)) max(12px,env(safe-area-inset-bottom)) max(16px,env(safe-area-inset-left));overflow:hidden;box-sizing:border-box}
#overlay .modal:has(.wheel-stage)>[data-action="close-modal"]{display:none}
.wheel-stage{height:100%;display:grid;grid-template-rows:auto minmax(0,1fr) auto;gap:12px;text-align:center}
.wheel-stage header h2{font-size:clamp(24px,4vw,40px);margin:6px 0;overflow-wrap:anywhere}
.wheel-stage header p{font-size:14px}
.wheel-stage main{min-width:0;min-height:0;display:flex;align-items:center;justify-content:center;padding:12px;container-type:size}
#overlay .wheel-stage .wheel-shell{width:min(100cqw,100cqh);height:min(100cqw,100cqh);max-width:100%;max-height:100%;aspect-ratio:1;margin:0;flex:none}
#overlay .wheel-stage .wheel{display:block;width:100%;height:100%;max-height:100%;object-fit:contain}
.wheel-stage footer{display:flex;flex-direction:column;gap:8px;border:0;padding:0;margin:0;align-items:center}
.wheel-stage footer .btn{width:min(100%,640px);font-size:clamp(18px,2vw,24px);min-height:56px}
.wheel-stage footer .back{margin:0;min-height:36px}
@media(min-aspect-ratio:4/3){.wheel-stage{grid-template-columns:minmax(0,1.6fr) minmax(240px,1fr);grid-template-rows:1fr 1fr;column-gap:24px}.wheel-stage main{grid-column:1;grid-row:1/3}.wheel-stage header{grid-column:2;grid-row:1;align-self:end}.wheel-stage footer{grid-column:2;grid-row:2;align-self:start}}
`;document.head.append(cashierStyle);
