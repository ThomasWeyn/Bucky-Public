"""Measure the real stdio worker with synthetic audio; never use microphone/history."""
import json
import os
import select
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def measure():
    scratch = tempfile.TemporaryDirectory(prefix='bucky-latency-worker-')
    process = subprocess.Popen(
        [str(ROOT / '.venv/bin/python'), '-B', '-u', str(ROOT / 'worker.py')],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'TMPDIR': scratch.name},
    )

    def receive():
        if not select.select([process.stdout], [], [], 120)[0]:
            raise TimeoutError('Worker did not respond')
        line = process.stdout.readline()
        if not line:
            raise RuntimeError('Worker exited before responding')
        message = json.loads(line)
        if message['event'] in ('fatal', 'error'):
            raise RuntimeError('Worker reported an error')
        return message

    try:
        started = time.monotonic()
        assert receive()['event'] == 'loading'
        assert receive()['event'] == 'ready'
        startup = time.monotonic() - started
        samples = []
        for index in range(4):
            started = time.monotonic()
            process.stdin.write(json.dumps({
                'id': str(index), 'path': str(ROOT / 'tests/dutch.wav'),
            }) + '\n')
            process.stdin.flush()
            result = receive()
            samples.append(time.monotonic() - started)
            assert result['event'] == 'result' and result['id'] == str(index)
            words = result['text'].lower()
            assert 'afspraak' in words and 'documenten' in words, 'Recognition failed'
        return {'startup_seconds': startup, 'first_seconds': samples[0],
                'warm_seconds': statistics.median(samples[1:])}
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()
        process.stderr.close()
        scratch.cleanup()


if __name__ == '__main__':
    runs = [measure() for _ in range(3)]
    first = statistics.median(r['first_seconds'] for r in runs)
    warm = statistics.median(r['warm_seconds'] for r in runs)
    report = {'runs': runs, 'median_first_seconds': first,
              'median_warm_seconds': warm, 'first_to_warm_ratio': first / warm,
              'recognition_pass': True, 'latency_pass': first / warm < 1.45}
    print(json.dumps(report, indent=2), flush=True)
    sys.exit(0 if report['latency_pass'] else 1)
