// Locally synthesized audio. Starts only after a user gesture; no audio files or tracking.
(() => {
 let ctx=null,master=null,enabled=localStorage.getItem('gf-sound-enabled')!=='false';
 const voices=new Set();
 function unlock(){if(!enabled)return;try{const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)return;ctx??=new Audio();if(!master){master=ctx.createGain();master.gain.value=.45;master.connect(ctx.destination)}if(ctx.state==='suspended')return ctx.resume().catch(()=>{})}catch{}}
 function stop(){for(const o of [...voices]){try{o.stop();o.disconnect()}catch{}voices.delete(o)}}
 function tone(f,at,length=.04,type='triangle',volume=.14){if(!enabled||!ctx||!master||ctx.state!=='running')return;try{const o=ctx.createOscillator(),g=ctx.createGain(),t=ctx.currentTime+at;o.type=type;o.frequency.setValueAtTime(f,t);g.gain.setValueAtTime(.0001,t);g.gain.exponentialRampToValueAtTime(volume,t+.006);g.gain.exponentialRampToValueAtTime(.0001,t+length);o.connect(g);g.connect(master);voices.add(o);o.onended=()=>{voices.delete(o);o.disconnect();g.disconnect()};o.start(t);o.stop(t+length+.01)}catch{}}
 function spin(ms=4100){stop();if(!enabled)return;for(let t=0;t<ms-130;t+=45+210*Math.pow(t/ms,2))tone(1100-350*t/ms,t/1000,.028,'triangle',.12)}
 function celebrate(){stop();if(!enabled)return;[523.25,659.25,783.99,1046.5].forEach((f,i)=>tone(f,i*.105,.25,'triangle',.15));[1046.5,1318.5,1568].forEach(f=>tone(f,.47,.58,'sine',.075))}
 function refresh(){document.querySelectorAll('.gf-audio-toggle').forEach(b=>{b.setAttribute('aria-pressed',String(enabled));b.setAttribute('aria-label',enabled?'Silenciar sonidos de la ruleta':'Activar sonidos de la ruleta');b.title=enabled?'Silenciar sonidos':'Activar sonidos';b.innerHTML='<span aria-hidden="true" style="font-size:21px">'+(enabled?'🔊':'🔇')+'</span><span>'+ (enabled?'Sonido':'Sin sonido')+'</span>'})}
 function button(extra){const b=document.createElement('button');b.type='button';b.className='gf-audio-toggle '+extra;b.addEventListener('click',()=>{enabled=!enabled;localStorage.setItem('gf-sound-enabled',String(enabled));if(!enabled)stop();else unlock();refresh()});return b}
 document.querySelector('.nav')?.append(button('gf-audio-desktop'));
 document.querySelector('.bottom-nav')?.append(button('gf-audio-mobile'));
 const style=document.createElement('style');style.textContent='.gf-audio-toggle{display:inline-flex;align-items:center;justify-content:center;gap:6px;min-width:44px;min-height:44px}.gf-audio-mobile{flex-direction:column}.gf-audio-desktop span:last-child{font-size:12px}@media(max-width:760px){.nav .gf-audio-desktop{display:none}}';document.head.append(style);refresh();
 document.addEventListener('visibilitychange',()=>{if(document.hidden)stop()});
 window.GraneroAudio={unlock,spin,celebrate,stop,get enabled(){return enabled}};
})();
