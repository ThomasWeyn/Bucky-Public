"""Exercise the production recording timer with a simulated elapsed clock."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "Sources/main.swift").read_text()
start = source.index("timer = Timer.scheduledTimer(withTimeInterval: 0.08")
body = source[start:].split("{ [weak self] _ in", 1)[1].split("\n            }", 1)[0]
harness = r"""
import Foundation
final class Meter {
    func updateMeters() {}
    func averagePower(forChannel: Int) -> Float { -20 }
}
final class State { var elapsed = 0; var level: CGFloat = 0; var recording = true }
final class Recording {
    let state = State()
    var recorder: Meter? = Meter()
    var started = Date()
    var stopCalls = 0
    func stop() { stopCalls += 1; state.recording = false }
    func tick() {
        let callback: () -> Void = { [weak self] in
""" + body + r"""
        }
        callback()
    }
}
for seconds in [299, 300, 301, 600, 3600, 86400] {
    let recording = Recording()
    recording.started = Date().addingTimeInterval(-Double(seconds))
    recording.tick()
    guard recording.state.recording && recording.stopCalls == 0 else {
        fputs("FAIL: recording stopped automatically at \(seconds) seconds\n", stderr)
        exit(1)
    }
    guard recording.state.elapsed >= seconds else { fatalError("Clock did not advance") }
}
print("Recording timer passed: still recording at 5 minutes, 10 minutes, 1 hour and 24 hours (simulated clock).")
"""
with tempfile.TemporaryDirectory(prefix="bucky-timer-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(harness)
    subprocess.run(["xcrun", "swift", str(path)], check=True)
