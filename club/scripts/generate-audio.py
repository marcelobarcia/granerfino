import math,struct,wave
from pathlib import Path
RATE=22050
out=Path('dist/audio');out.mkdir(parents=True,exist_ok=True)
def save(name,duration,notes):
 samples=[0.0]*int(RATE*duration)
 for freq,start,length,amplitude in notes:
  for i in range(int(length*RATE)):
   n=int(start*RATE)+i
   if n>=len(samples):break
   t=i/RATE;env=min(1,t/.004)*math.exp(-5*t/length)
   samples[n]+=amplitude*env*(math.sin(2*math.pi*freq*t)+.25*math.sin(4*math.pi*freq*t))
 peak=max(map(abs,samples)) or 1
 with wave.open(str(out/name),'wb') as f:
  f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
  f.writeframes(b''.join(struct.pack('<h',round(x*.85/peak*32767)) for x in samples))
notes=[];t=0
while t<3.97:
 notes.append((1050-300*t/4.1,t,.035,.75));t+=.045+.21*(t/4.1)**2
save('spin.wav',4.1,notes)
save('win.wav',1.25,[(f,i*.11,.3,.48) for i,f in enumerate([523.25,659.25,783.99,1046.5])]+[(f,.5,.65,.23) for f in [1046.5,1318.5,1568]])
save('try-again.wav',.55,[(659.25,0,.24,.4),(523.25,.16,.3,.4)])
