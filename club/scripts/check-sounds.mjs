import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
let created=0,played=[],buttons=[],paused=0;const preferences=new Map();
class Audio {constructor(){created++;this.src=''}setAttribute(){}play(){played.push(this.src);return Promise.resolve()}pause(){paused++}}
const doc={baseURI:'https://example.test/club/',querySelector:()=>({append(b){buttons.push(b)}}),querySelectorAll:()=>buttons,createElement:()=>({handlers:{},addEventListener(k,f){this.handlers[k]=f},setAttribute(){}}),head:{append(){}},addEventListener(){}};
const window={};vm.runInNewContext(fs.readFileSync('dist/sounds.js','utf8'),{window,document:doc,Audio,URL,location:{href:doc.baseURI},localStorage:{getItem:k=>preferences.get(k),setItem:(k,v)=>preferences.set(k,v)}});
const a=window.GraneroAudio;assert.equal(created,0);await a.unlock();await a.spin();assert.ok(played.at(-1).endsWith('/club/audio/spin.wav'));await a.finish(true);assert.ok(played.at(-1).endsWith('/win.wav'));await a.finish(false);assert.ok(played.at(-1).endsWith('/try-again.wav'));
buttons[0].handlers.click();const n=played.length;await a.spin();assert.equal(played.length,n);assert.equal(preferences.get('gf-sound-enabled'),'false');await a.test();assert.equal(a.enabled,true);assert.ok(played.length>n);assert.ok(paused>0);
for(const f of ['spin','win','try-again']){const b=fs.readFileSync('dist/audio/'+f+'.wav');assert.equal(b.toString('ascii',0,4),'RIFF');assert.equal(b.toString('ascii',8,12),'WAVE');let peak=0;for(let i=44;i<b.length;i+=2)peak=Math.max(peak,Math.abs(b.readInt16LE(i)));assert.ok(peak>15000,f+' must contain audible-level samples')}
console.log('Media audio, playable WAV files, gesture start, mute and test sound passed.');
