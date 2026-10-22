"""Reuse completed local PCM windows while Bucky is recording.

Only the app's private temporary recording directory is watched. No microphone,
network, disk transcript cache, or early text delivery. Inference stays on the
worker's one model thread. Final chunks and overlap merging match parakeet-mlx
0.5.3's BaseParakeet.transcribe (30 s / 3 s); its public helpers do the merging.
"""
import hashlib
import os
import re
import stat
import struct
import tempfile
import time
from dataclasses import dataclass, replace
from pathlib import Path

import mlx.core as mx
import numpy as np
from parakeet_mlx.alignment import (
    merge_longest_common_subsequence,
    merge_longest_contiguous,
    sentences_to_result,
    tokens_to_sentences,
)
from parakeet_mlx.audio import get_logmel

RATE = 16000
WINDOW = 30 * RATE
STEP = 27 * RATE
LOOKAHEAD = RATE // 2
NAME = re.compile(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.wav', re.I)


def identity(info):
    return (info.st_dev, info.st_ino, getattr(info, 'st_birthtime', None))


def pcm_offset(stream):
    """Find native mono PCM16 data, ignoring an unfinished WAV data-size field."""
    header = stream.read(12)
    if len(header) != 12 or header[:4] != b'RIFF' or header[8:] != b'WAVE':
        return None
    valid_format = False
    # Bound header parsing, never scan the audio payload looking for markers.
    while stream.tell() < 1024 * 1024:
        chunk = stream.read(8)
        if len(chunk) != 8:
            return None
        kind, size = struct.unpack('<4sI', chunk)
        if kind == b'data':
            return stream.tell() if valid_format else None
        if kind == b'fmt ':
            if size < 16 or size > 4096:
                return None
            fmt = stream.read(size)
            if len(fmt) != size:
                return None
            tag, channels, rate, byte_rate, align, bits = struct.unpack('<HHIIHH', fmt[:16])
            valid_format = (tag == 1 and channels == 1 and rate == RATE
                            and byte_rate == RATE * 2 and align == 2 and bits == 16)
            if size % 2:
                stream.seek(1, 1)
        else:
            stream.seek(size + size % 2, 1)
    return None


def fingerprint(audio):
    return hashlib.sha256(audio.tobytes()).digest()


@dataclass
class CachedWindow:
    digest: bytes
    tokens: list


class ProgressiveTranscriber:
    def __init__(self, model, directory=None):
        self.model = model
        spool = Path(directory) if directory else Path(tempfile.gettempdir()) / 'nl.quickmouse.spreek'
        self.directory = spool.parent.resolve() / spool.name
        self.started = time.time()
        self.blocked = None
        self.clear()

    def clear(self):
        self.path = None
        self.file_id = None
        self.windows = []
        self.largest_size = 0

    def disable_current(self):
        self.blocked = self.file_id
        self.clear()

    def _candidates(self):
        try:
            folder = self.directory.lstat()
            if (not stat.S_ISDIR(folder.st_mode) or folder.st_uid != os.getuid()
                    or folder.st_mode & 0o077):
                return []
            candidates = []
            for path in self.directory.glob('*.wav'):
                if not NAME.fullmatch(path.name):
                    continue
                info = path.lstat()
                created = getattr(info, 'st_birthtime', info.st_mtime)
                if (stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                        and not info.st_mode & 0o077 and created >= self.started):
                    candidates.append((path, info))
            return candidates
        except OSError:
            return []

    def poll(self):
        """Prepare at most one full window; requests get priority between windows."""
        candidates = self._candidates()
        if len(candidates) != 1:
            self.blocked = None
            self.clear()
            return 0
        path, info = candidates[0]
        if identity(info) == self.blocked:
            return 0
        if self.path != path or self.file_id != identity(info):
            self.clear()
            self.path, self.file_id = path, identity(info)
        if info.st_size < self.largest_size:
            self.clear()
            return 0
        self.largest_size = info.st_size
        start = len(self.windows) * STEP
        # O_NOFOLLOW and fstat avoid following a replacement/symlink after lstat.
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, 'rb') as stream:
                opened = os.fstat(stream.fileno())
                if identity(opened) != self.file_id:
                    self.clear()
                    return 0
                offset = pcm_offset(stream)
                if offset is None or (opened.st_size - offset) // 2 < start + WINDOW + LOOKAHEAD:
                    return 0
                stream.seek(offset + start * 2)
                raw = stream.read(WINDOW * 2)
            if len(raw) != WINDOW * 2:
                return 0
            audio = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768.0
            result = self.model.generate(get_logmel(mx.array(audio), self.model.preprocessor_config))[0]
            # Cancellation/removal during inference must not leave a reusable cache.
            if identity(path.lstat()) != self.file_id:
                self.clear()
                return 0
            self.windows.append(CachedWindow(fingerprint(audio), result.tokens))
            return len(self.windows)
        except (OSError, ValueError, struct.error):
            self.clear()
            return 0

    def finish(self, path, audio, rate, subtype):
        """Return (text, reused, remaining), or None for the ordinary batch route."""
        if (rate != RATE or audio.ndim != 1 or subtype != 'PCM_16'
                or len(audio) <= WINDOW or self.path != path or not self.windows):
            return None
        try:
            if identity(path.lstat()) != self.file_id:
                return None
        except OSError:
            return None
        # Verify the final samples, not just the name/size/mtime. A replaced or
        # edited prefix is never combined with a cached transcript.
        for index, cached in enumerate(self.windows):
            start = index * STEP
            if len(audio) < start + WINDOW or fingerprint(audio[start:start + WINDOW]) != cached.digest:
                return None
        tokens = []
        reused = remaining = 0
        for index, start in enumerate(range(0, len(audio), STEP)):
            end = min(start + WINDOW, len(audio))
            if end - start < self.model.preprocessor_config.hop_length:
                break
            if index < len(self.windows):
                local = self.windows[index].tokens
                reused += 1
            else:
                result = self.model.generate(get_logmel(mx.array(audio[start:end]), self.model.preprocessor_config))[0]
                local = result.tokens
                remaining += 1
            shifted = [replace(token, start=token.start + start / RATE) for token in local]
            if tokens:
                try:
                    tokens = merge_longest_contiguous(tokens, shifted, overlap_duration=3)
                except RuntimeError:
                    tokens = merge_longest_common_subsequence(tokens, shifted, overlap_duration=3)
            else:
                tokens = shifted
        return sentences_to_result(tokens_to_sentences(tokens)).text.strip(), reused, remaining
