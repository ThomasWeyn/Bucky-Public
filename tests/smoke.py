import json, os, selectors, subprocess, tempfile, time
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
# Fresh clones recreate synthetic fixtures; no personal recordings are needed.
for name, voice, text in [
    ('dutch', 'Xander', 'Goedemorgen, ik wil vandaag een afspraak maken voor volgende week. Kun je de documenten alvast klaarzetten?'),
    ('english', 'Samantha', 'Please send the updated project notes before our meeting tomorrow. I would like to review the next steps.'),
]:
    fixture = ROOT/'tests'/f'{name}.aiff'
    if not fixture.exists():
        subprocess.run(['say', '-v', voice, '-o', str(fixture), text], check=True)
clips=[]
for name in ('dutch','english'):
    audio,sr=sf.read(ROOT/'tests'/f'{name}.aiff')
    audio=resample_poly(audio,16000,sr)
    sf.write(ROOT/'tests'/f'{name}.wav',audio,16000)
    clips.append(audio)
sf.write(ROOT/'tests/mixed.wav',np.concatenate([clips[0],np.zeros(8000),clips[1]]),16000)
sf.write(ROOT/'tests/silence.wav',np.zeros(32000),16000)
p=subprocess.Popen([str(ROOT/'.venv/bin/python'),'-u','worker.py'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
def receive(timeout=120):
    selector=selectors.DefaultSelector(); selector.register(p.stdout,selectors.EVENT_READ)
    try:
        if not selector.select(timeout): raise TimeoutError('Worker did not respond')
        line=p.stdout.readline()
        if not line: raise RuntimeError(p.stderr.read())
        return json.loads(line)
    finally: selector.close()
results=[]
try:
    assert receive()['event']=='loading'
    assert receive()['event']=='ready'
    for name in ['dutch','english','mixed','silence','missing']:
        p.stdin.write(json.dumps({'id':name,'path':str(ROOT/'tests'/f'{name}.wav')})+'\n');p.stdin.flush()
        result=receive(); print(json.dumps(result,ensure_ascii=False),flush=True);results.append(result)
        if name=='missing': assert result['event']=='error'
        elif name=='silence': assert result['text']==''
        else:
            assert result['event']=='result'
            text=result['text'].lower()
            if name in ('dutch','mixed'): assert 'afspraak' in text and 'documenten' in text, text
            if name in ('english','mixed'): assert 'meeting' in text and 'project' in text, text
    # A real >5-minute file must reach the model, including speech at its end.
    with tempfile.TemporaryDirectory(prefix='bucky-long-') as directory:
        path = Path(directory) / 'long.wav'
        audio = np.zeros(330 * 16000)
        audio[:len(clips[0])] = clips[0]
        audio[-len(clips[1]):] = clips[1]
        sf.write(path, audio, 16000)
        p.stdin.write(json.dumps({'id':'long','path':str(path)})+'\n');p.stdin.flush()
        result=receive(timeout=360);results.append(result)
        assert result['event']=='result', result
        text=result['text'].lower()
        assert 'afspraak' in text and 'documenten' in text, text
        assert 'meeting' in text and 'project' in text, text
        print(json.dumps({'test':'330-second synthetic recording','event':result['event'],'seconds':result['seconds'],'beginning_and_end_recognized':True}),flush=True)
    (ROOT/'tests/results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
finally:
    p.stdin.close();p.wait(timeout=10)
