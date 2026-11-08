// Media audio plays on iPad/iPhone as well as desktop, only after a user gesture.
(() => {
 let player=null,enabled=localStorage.getItem('gf-sound-enabled')!=='false';
 const src=name=>new URL('./audio/'+name,document.baseURI||location.href).href;
 function media(){if(!player){player=new Audio();player.preload='auto';player.volume=.8;player.setAttribute('playsinline','')}return player}
 function stop(){if(player){player.pause();player.loop=false}}
 function play(name,loop=false){if(!enabled)return Promise.resolve();try{const a=media();a.pause();a.src=src(name);a.loop=loop;a.currentTime=0;const p=a.play();return p?.then(()=>true).catch(e=>{if(e.name!=='AbortError'&&typeof toast==='function')toast('Tocá “Probar sonido” y revisá el volumen del dispositivo');return false})||Promise.resolve(true)}catch{return Promise.resolve()}}
 function unlock(){return enabled?play('spin.wav',true):Promise.resolve()}
 function spin(){return play('spin.wav')}
 function celebrate(){return play('win.wav')}
 function finish(won=true){return play(won?'win.wav':'try-again.wav')}
 function test(){enabled=true;localStorage.setItem('gf-sound-enabled','true');refresh();return play('win.wav').then(ok=>{if(typeof toast==='function')toast(ok?'Reproduciendo sonido de prueba':'No se pudo reproducir. Revisá el volumen o abrí en Safari/Chrome')})}
 function refresh(){document.querySelectorAll('.gf-audio-toggle').forEach(b=>{b.setAttribute('aria-pressed',String(enabled));b.setAttribute('aria-label',enabled?'Silenciar sonidos de la ruleta':'Activar sonidos de la ruleta');b.title=enabled?'Silenciar sonidos':'Activar sonidos';b.innerHTML='<span aria-hidden="true" style="font-size:21px">'+(enabled?'🔊':'🔇')+'</span><span>'+(enabled?'Sonido':'Sin sonido')+'</span>'})}
 function button(extra){const b=document.createElement('button');b.type='button';b.className='gf-audio-toggle '+extra;b.addEventListener('click',()=>{enabled=!enabled;localStorage.setItem('gf-sound-enabled',String(enabled));if(!enabled)stop();else test();refresh()});return b}
 document.querySelector('.nav')?.append(button('gf-audio-desktop'));document.querySelector('.bottom-nav')?.append(button('gf-audio-mobile'));
 document.addEventListener('click',e=>{if(e.target.closest('[data-action="test-sound"]'))test()});
 const style=document.createElement('style');style.textContent='.gf-audio-toggle{display:inline-flex;align-items:center;justify-content:center;gap:6px;min-width:44px;min-height:44px}.gf-audio-mobile{flex-direction:column}.gf-audio-desktop span:last-child{font-size:12px}@media(max-width:760px){.nav .gf-audio-desktop{display:none}}';document.head.append(style);refresh();document.addEventListener('visibilitychange',()=>{if(document.hidden)stop()});
 window.GraneroAudio={unlock,spin,celebrate,finish,test,stop,get enabled(){return enabled}};
})();
