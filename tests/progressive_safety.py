"""Cache cancellation, identity, scope and native Apple WAV-format checks."""
import io
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import uuid
import wave
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parakeet_mlx.alignment import AlignedToken
from progressive import ProgressiveTranscriber, pcm_offset


class FakeModel:
    preprocessor_config = SimpleNamespace(hop_length=160)
    calls = 0

    def generate(self, audio):
        self.calls += 1
        return [SimpleNamespace(tokens=[AlignedToken(1, ' Test.', 0, .1)])]


class CacheSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='bucky-cache-safety-')
        self.folder = Path(self.tmp.name) / 'nl.quickmouse.spreek'
        self.folder.mkdir(mode=0o700)
        self.model = FakeModel()
        self.cache = ProgressiveTranscriber(self.model, self.folder)
        self.audio = np.zeros(34 * 16000, dtype=np.float32)
        self.path = self.folder / (str(uuid.uuid4()) + '.wav')
        self.write(self.path)
        self.mel = patch('progressive.get_logmel', side_effect=lambda audio, config: audio)
        self.mel.start()

    def write(self, path):
        with wave.open(str(path), 'wb') as out:
            out.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            out.writeframes((self.audio * 32768).astype('<i2').tobytes())
        path.chmod(0o600)

    def tearDown(self):
        self.mel.stop()
        self.tmp.cleanup()

    def test_pause_does_not_recompute_and_finish_preserves_cache_tokens(self):
        self.assertEqual(self.cache.poll(), 1)
        self.assertEqual(self.cache.poll(), 0)
        self.assertEqual(self.model.calls, 1)
        before = self.cache.windows[0].tokens[0].start
        result = self.cache.finish(self.path.resolve(), self.audio, 16000, 'PCM_16')
        self.assertEqual(result[1:], (1, 1))
        self.assertEqual(self.cache.windows[0].tokens[0].start, before)

    def test_cancel_drops_transcript_cache(self):
        self.cache.poll()
        self.path.unlink()
        self.cache.poll()
        self.assertEqual(self.cache.windows, [])
        self.assertIsNone(self.cache.path)

    def test_modified_prefix_requires_batch(self):
        self.cache.poll()
        changed = self.audio.copy()
        changed[2] = .25
        self.assertIsNone(self.cache.finish(self.path.resolve(), changed, 16000, 'PCM_16'))

    def test_replaced_inode_requires_batch(self):
        self.cache.poll()
        replacement = self.folder / 'replacement'
        self.write(replacement)
        replacement.replace(self.path)
        self.assertIsNone(self.cache.finish(self.path.resolve(), self.audio, 16000, 'PCM_16'))

    def test_old_file_is_ignored(self):
        self.cache.started = self.path.stat().st_birthtime + 1
        self.assertEqual(self.cache.poll(), 0)

    def test_unrelated_names_and_readable_files_are_ignored(self):
        self.path.chmod(0o644)
        self.assertEqual(self.cache.poll(), 0)
        self.path.rename(self.folder / 'not-a-bucky-recording.wav')
        self.assertEqual(self.cache.poll(), 0)

    def test_file_symlink_is_ignored(self):
        target = self.folder.parent / 'other.wav'
        self.path.rename(target)
        self.path.symlink_to(target)
        self.assertEqual(self.cache.poll(), 0)

    def test_directory_symlink_is_ignored(self):
        alias = self.folder.parent / 'alias'
        alias.symlink_to(self.folder, target_is_directory=True)
        cache = ProgressiveTranscriber(self.model, alias)
        cache.started = self.cache.started
        self.assertEqual(cache.poll(), 0)

    def test_ambiguous_recordings_are_not_preprocessed(self):
        self.write(self.folder / (str(uuid.uuid4()) + '.wav'))
        self.assertEqual(self.cache.poll(), 0)

    def test_failure_does_not_repeat_expensive_work(self):
        self.cache.poll()
        self.cache.disable_current()
        self.assertEqual(self.cache.poll(), 0)
        self.assertEqual(self.model.calls, 1)

    def test_other_format_and_shorter_final_file_require_batch(self):
        self.cache.poll()
        self.assertIsNone(self.cache.finish(self.path.resolve(), self.audio, 44100, 'PCM_16'))
        self.assertIsNone(self.cache.finish(self.path.resolve(), self.audio, 16000, 'FLOAT'))
        self.assertIsNone(self.cache.finish(self.path.resolve(), self.audio[:100], 16000, 'PCM_16'))

    def test_unfinished_header_with_padding(self):
        fmt = struct.pack('<HHIIHH', 1, 1, 16000, 32000, 2, 16)
        header = b'RIFF' + struct.pack('<I', 0) + b'WAVE'
        header += b'JUNK' + struct.pack('<I', 3) + b'abc\0'
        header += b'fmt ' + struct.pack('<I', 16) + fmt
        header += b'data' + struct.pack('<I', 0)
        self.assertEqual(pcm_offset(io.BytesIO(header)), len(header))
        self.assertIsNone(pcm_offset(io.BytesIO(header[:20])))

    def test_native_coreaudio_growing_wav(self):
        source = Path(self.tmp.name) / 'writer.swift'
        native = Path(self.tmp.name) / 'native.wav'
        source.write_text('''import Foundation
import AVFoundation
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
var file: AVAudioFile? = try AVAudioFile(forWriting: URL(fileURLWithPath: CommandLine.arguments[1]), settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
let frames = AVAudioFrameCount(31 * 16000)
let buffer = AVAudioPCMBuffer(pcmFormat: file!.processingFormat, frameCapacity: frames)!
buffer.frameLength = frames
buffer.int16ChannelData![0].update(repeating: 0, count: Int(frames))
try file!.write(from: buffer)
print("written")
fflush(stdout)
_ = readLine()
file = nil
''')
        sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
        command = ['xcrun', 'swift']
        if Path(sdk).is_dir():
            command += ['-sdk', sdk]
        process = subprocess.Popen(command + [str(source), str(native)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(process.stdout.readline().strip(), 'written')
            with native.open('rb') as stream:
                offset = pcm_offset(stream)
                self.assertIsNotNone(offset)
                self.assertGreaterEqual(native.stat().st_size - offset, 30 * 16000 * 2)
        finally:
            process.stdin.close()
            process.wait(timeout=20)
            process.stdout.close()
            process.stderr.close()
        self.assertEqual(process.returncode, 0)


if __name__ == '__main__':
    unittest.main()
