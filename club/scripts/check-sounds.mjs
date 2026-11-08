import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
let contexts=0,started=[],stopped=0,buttons=[];const preferences=new Map();
class AudioContext {
 constructor(){contexts++;this.state='running';this.currentTime=2;this.destination={}}
 createGain(){return {gain:{value:0,setValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){},disconnect(){}}}
 createOscillator(){return {frequency:{setValueAtTime(){}},connect(){},disconnect(){},start(t){started.push(t)},stop(){stopped++}}}
 resume(){this.state='running';return Promise.resolve()}
}
const doc={querySelector:()=>({append(b){buttons.push(b)}}),querySelectorAll:()=>buttons,createElement:()=>({handlers:{},addEventListener(k,f){this.handlers[k]=f},setAttribute(){}}),head:{append(){}},addEventListener(){}};
const window={AudioContext};
vm.runInNewContext(fs.readFileSync('dist/sounds.js','utf8'),{window,document:doc,localStorage:{getItem:k=>preferences.get(k),setItem:(k,v)=>preferences.set(k,v)}});
const audio=window.GraneroAudio;assert.equal(contexts,0,'No autoplay before a gesture');assert.equal(buttons.length,2);
await audio.unlock();audio.spin();assert.ok(started.length>25);assert.ok(started.every((v,i)=>i===0||v>started[i-1]));assert.ok((started.at(-1)-started.at(-2))>(started[1]-started[0]),'Ticks slow down');
const before=started.length;audio.celebrate();assert.equal(started.length-before,7);assert.ok(stopped>0);
buttons[0].handlers.click();assert.equal(audio.enabled,false);assert.equal(preferences.get('gf-sound-enabled'),'false');const count=started.length;audio.spin();audio.celebrate();assert.equal(started.length,count,'Mute prevents audio');
buttons[1].handlers.click();assert.equal(audio.enabled,true);assert.equal(contexts,1);audio.celebrate();assert.equal(started.length-count,7);
console.log('Sound checks passed: gesture, slowing ticks, celebration, mute and saved preference.');
