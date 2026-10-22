"""Real worker, synthetic growing WAV; measures stop-to-result, never microphone/history."""
import argparse
import json
import os
import select
import subprocess
import tempfile
import time
import uuid
import wave
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]


def run(seconds=90, realtime=False):
    clips = [sf.read(ROOT / 'tests' / (name + '.wav'), dtype='int16')[0]
             for name in ('dutch', 'english')]
    audio = np.tile(np.concatenate(clips), int(seconds * 16000 / sum(map(len, clips))) + 2)[:seconds * 16000]
    with tempfile.TemporaryDirectory(prefix='bucky-progressive-test-') as tmp:
        base = Path(tmp)
        spool = base / 'nl.quickmouse.spreek'
        spool.mkdir(mode=0o700)
        process = subprocess.Popen(
            [str(ROOT / '.venv/bin/python'), '-B', '-u', str(ROOT / 'worker.py')],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={**os.environ, 'TMPDIR': tmp, 'PYTHONDONTWRITEBYTECODE': '1'},
            bufsize=0,
        )
        buffer = bytearray()

        def receive(timeout=120):
            deadline = time.monotonic() + timeout
            while b'\n' not in buffer:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                    raise TimeoutError('No worker progress/result within budget')
                data = os.read(process.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError('Worker exited')
                buffer.extend(data)
            line, _, rest = buffer.partition(b'\n')
            buffer[:] = rest
            message = json.loads(line)
            if message['event'] in ('fatal', 'error'):
                raise RuntimeError('Worker returned ' + message['event'])
            return message

        def submit(path, request_id):
            process.stdin.write((json.dumps({'id': request_id, 'path': str(path)}) + '\n').encode())

        try:
            assert receive()['event'] == 'loading'
            assert receive()['event'] == 'ready'
            path = spool / (str(uuid.uuid4()).upper() + '.wav')
            with path.open('wb') as raw:
                path.chmod(0o600)
                with wave.open(raw, 'wb') as recording:
                    recording.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                    written = 0
                    completed = 0
                    began_recording = time.monotonic()
                    while written < len(audio):
                        # Leave 0.5 seconds beyond each full 30-second window.
                        end = min(len(audio), int((30.5 + completed * 27) * 16000))
                        if realtime:
                            while written < end:
                                next_end = min(end, written + 8000)
                                deadline = began_recording + next_end / 16000
                                time.sleep(max(0, deadline - time.monotonic()))
                                recording.writeframesraw(audio[written:next_end].astype('<i2').tobytes())
                                raw.flush()
                                written = next_end
                        else:
                            recording.writeframesraw(audio[written:end].astype('<i2').tobytes())
                            raw.flush()
                            written = end
                        if end < len(audio):
                            message = receive(timeout=8)
                            assert message['event'] == 'prepared', 'No speculative result may be delivered'
                            completed += 1
                            assert message['chunks'] == completed
                        else:
                            break
            stopped = time.monotonic()
            submit(path, 'progressive')
            result = receive()
            while result['event'] == 'prepared':
                result = receive()
            stop_seconds = time.monotonic() - stopped
            assert result['event'] == 'result' and result['id'] == 'progressive'
            assert result.get('reused_chunks', 0) >= completed >= 2
            # Completed file outside Bucky's watched spool forces ordinary batch work.
            batch = base / 'batch.wav'
            batch.write_bytes(path.read_bytes())
            path.unlink()
            began = time.monotonic()
            submit(batch, 'batch')
            reference = receive()
            batch_seconds = time.monotonic() - began
            assert reference['event'] == 'result' and reference['id'] == 'batch'
            assert reference.get('reused_chunks', 0) == 0
            assert result['text'] == reference['text'], 'Chunk boundaries changed the transcript'
            assert all(word in result['text'].lower() for word in ('afspraak', 'meeting'))
            report = {'audio_seconds': seconds, 'batch_seconds': round(batch_seconds, 3),
                      'stop_to_result_seconds': round(stop_seconds, 3),
                      'reused_chunks': result['reused_chunks'],
                      'remaining_chunks': result['remaining_chunks'], 'identical_text': True,
                      'speedup': round(batch_seconds / stop_seconds, 2), 'real_time_capture': realtime}
            print(json.dumps(report), flush=True)
            assert stop_seconds < batch_seconds * 0.5, 'Long-recording stop latency did not halve'
            return report
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stdout.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=int, default=90)
    parser.add_argument('--realtime', action='store_true')
    options = parser.parse_args()
    run(options.seconds, options.realtime)
