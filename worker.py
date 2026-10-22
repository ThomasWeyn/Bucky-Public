"""Private stdio worker. No server, telemetry, transcript storage, or uploads."""
import os, sys, json, time
from pathlib import Path
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
os.environ['DO_NOT_TRACK'] = '1'
ROOT = Path(__file__).resolve().parent
MODEL = ROOT / 'model'

def emit(**payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)

def main():
    import imageio_ffmpeg
    # parakeet's loader calls ffmpeg by name; provide a private executable link.
    bindir = ROOT / '.bin'
    bindir.mkdir(exist_ok=True)
    ffmpeg = bindir / 'ffmpeg'
    if not ffmpeg.exists():
        ffmpeg.symlink_to(imageio_ffmpeg.get_ffmpeg_exe())
    os.environ['PATH'] = str(bindir) + os.pathsep + os.environ.get('PATH', '')
    if '--download' in sys.argv:
        from huggingface_hub import snapshot_download
        snapshot_download('mlx-community/parakeet-tdt-0.6b-v3', revision='ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15', local_dir=MODEL)
        return
    os.environ['HF_HUB_OFFLINE'] = '1'
    from parakeet_mlx import from_pretrained
    import mlx.core as mx
    import soundfile as sf
    import numpy as np
    emit(event='loading')
    model = from_pretrained(str(MODEL))
    emit(event='ready')
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            path = Path(request['path']).resolve()
            if not path.is_file():
                raise ValueError('Recording was not found. Please record again.')
            audio, sr = sf.read(path, dtype='float32')
            duration = len(audio) / sr
            start = time.monotonic()
            # Do not hallucinate a transcript from digital silence / very quiet clips.
            rms = float(np.sqrt(np.mean(audio ** 2))) if len(audio) else 0.0
            if duration < .25 or rms < .0005:
                text = ''
            else:
                text = model.transcribe(str(path), chunk_duration=30, overlap_duration=3).text.strip()
            emit(event='result', id=request.get('id'), text=text, seconds=round(time.monotonic()-start, 3))
            mx.clear_cache()
        except Exception as exc:
            emit(event='error', id=request.get('id'), message=str(exc))

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        emit(event='fatal', message=str(exc))
        sys.exit(1)
