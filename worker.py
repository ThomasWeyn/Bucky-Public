"""Private stdio worker. No server, telemetry, transcript storage, or uploads."""
import os, sys, json, time, queue, threading
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
    # MLX loads/evaluates lazily. Pay the first inference cost before advertising
    # readiness, using generated silence rather than microphone or stored speech.
    from parakeet_mlx.audio import get_logmel
    model.generate(get_logmel(mx.zeros(16000, dtype=mx.float32), model.preprocessor_config))
    mx.synchronize()
    from progressive import ProgressiveTranscriber
    progressive = ProgressiveTranscriber(model)
    requests = queue.Queue()

    def read_requests():
        for line in sys.stdin:
            requests.put(line)
        requests.put(None)

    threading.Thread(target=read_requests, daemon=True).start()
    emit(event='ready')
    while True:
        try:
            line = requests.get(timeout=.2)
        except queue.Empty:
            try:
                prepared = progressive.poll()
                if prepared:
                    emit(event='prepared', chunks=prepared)
                    mx.clear_cache()
            except Exception:
                # Speculative work is optional. The ordinary batch route remains
                # available; never log audio, transcript content, or file paths.
                progressive.disable_current()
            continue
        if line is None:
            break
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
            reused = remaining = 0
            if duration < .25 or rms < .0005:
                text = ''
            else:
                try:
                    prepared = progressive.finish(path, audio, sr, sf.info(path).subtype)
                except Exception:
                    prepared = None  # Cached work must never prevent a batch retry.
                if prepared is None:
                    text = model.transcribe(str(path), chunk_duration=30, overlap_duration=3).text.strip()
                else:
                    text, reused, remaining = prepared
            emit(event='result', id=request.get('id'), text=text,
                 seconds=round(time.monotonic()-start, 3),
                 reused_chunks=reused, remaining_chunks=remaining)
        except Exception as exc:
            emit(event='error', id=request.get('id'), message=str(exc))
        finally:
            progressive.clear()
            mx.clear_cache()

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        emit(event='fatal', message=str(exc))
        sys.exit(1)
