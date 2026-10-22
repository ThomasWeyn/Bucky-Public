# Bucky

Local Dutch and English dictation for Apple Silicon Macs (M1 or newer), macOS 14+.

This is a public source snapshot for reading, cloning and downloading. The repository is archived intentionally: it accepts no pull requests, issues or other contributions while archived. Future snapshots require a separate review and publication. It is source code, not a ready-made installer. Windows and Intel Macs are not supported.

## Install on a Mac without a ZIP file

On a managed Mac, use the software installation and permissions route approved by your organization.

1. Install Apple's Command Line Tools (`xcode-select --install`) and [uv](https://docs.astral.sh/uv/getting-started/installation/). If you already use Homebrew, `brew install uv` is one option.
2. Open Terminal and clone the public source into a permanent folder; GitHub sign-in is not needed:

   ```sh
   git clone https://github.com/ThomasWeyn/Bucky-Public.git
   cd Bucky-Public
   bash scripts/install.sh
   ```

3. The installer downloads an isolated Python 3.12 runtime, pinned packages and the pinned speech model, checks the model checksum and builds `~/Applications/Bucky.app`. Allow several GB of disk space and internet access for installation.
4. Open `~/Applications/Bucky.app` and grant Microphone and Accessibility. Configure your shortcut and, if wanted, enable startup at login in Settings.

Keep the source folder in place: the app runs its engine from that folder. After moving it, quit Bucky and deliberately rebuild with `BUCKY_REPLACE_APP=1 bash scripts/build.sh`. macOS may require renewed permissions after rebuilding. The build records the path of the clone on the installing Mac in the locally built app; no prebuilt app or originating device path is distributed here. Each Mac has its own settings and history.

## Build troubleshooting

If the compiler reports `SwiftUIMacros.StateMacro` missing, the selected Apple SDK and available compiler plug-ins do not match. Use compatible Apple Command Line Tools or Xcode. With the macOS 26.5 SDK already installed, this snapshot builds with:

```sh
SDKROOT="$(xcrun --sdk macosx26.5 --show-sdk-path)" bash scripts/install.sh
```

This selects an installed SDK for this command; it does not change the system toolchain. Snapshot build/signature checks used that SDK with Apple Swift 6.4. A fresh dependency installation on another physical Mac remains unverified.

## Use

- **Dictate:** click the microphone or use your shortcut. Press again to finish. There is no automatic recording time limit. Escape, quitting and sleep cancel recording.
- **History:** search, read, copy or delete transcripts. Individual deletion has Undo; deleting all requires confirmation.
- **Vocabulary:** edit spelling replacements or import UTF-8 CSV, TSV or text. A preview shows new and duplicate entries before adding them. Existing entries stay unchanged. The public default contains only `super whisper = Superwhisper`.
- **Snippets:** save distinctive spoken triggers for literal text, including several lines. Matching ignores case and respects whole phrases. Snippets take precedence over an identical vocabulary rule.
- **Settings:** permissions, keyboard/mouse shortcuts, hold-to-talk, recording sounds, startup at login, automatic paste and history controls.

The default shortcut is Control-Space; Control-Option-Space is a backup. A recorded user shortcut takes precedence. Side and middle mouse buttons can be captured; primary and secondary clicks are excluded. Quit another dictation app using the same shortcut before testing.

Automatic paste targets the original app only if it remains foreground. Bucky never presses Return. Changing fields within that app changes the paste destination. Otherwise, paste from the clipboard manually. An emitted paste keystroke does not guarantee insertion.

## New in 0.3

- **Clipboard restoration:** automatic paste restores the previous available clipboard representations after a short hold: normally 1.5 seconds, Word/Outlook 3 seconds, recognized remote clients 5 seconds. Restoration is skipped if you copied something new, or if a complete supported snapshot exceeds 16 MB/128 items. Explicit Copy and manual-paste fallback keep the transcript on the clipboard. Turn restoration off in Settings if wanted. Slow applications may still need manual paste.
- **Paste last dictation:** press Control–Command–V in the destination app to repeat the latest available result, even with automatic paste disabled. Settings reports shortcut conflicts. Clicking Paste last inside Bucky copies the text; it does not activate another application or press Return. With history saving off, a result survives only for the current app session.
- **Vocabulary import:** up to 1 MB/5,000 entries, one term or two columns (heard/preferred) per row. CSV quoting, TSV and plain `heard = preferred` lines are supported. Each field is single-line and at most 512 characters. Existing entries and duplicates are kept/skipped, with confirmation before additions. This replaces text after recognition; it does not train the speech model.
- **Snippets:** manage up to 200 enabled/disabled snippets with a trigger of at most 100 characters and text of at most 10,000 characters. Inserted text is literal and is not expanded recursively. Settings and snippets remain in local app preferences.
- **Long recordings:** completed 30-second PCM windows are processed locally while recording continues, with the original 3-second overlap. After stop, matching verified results are reused and the remaining tail is processed. Intermediate results stay in RAM. No extra audio copies or on-disk transcript cache are written. Unsupported/invalidated inputs use ordinary batch processing. This moves computation into recording time and does not promise lower total CPU/battery usage. Text is delivered only after explicit stop; there is no silence-based automatic stop.

Command–1/2/3/4 retain Dictate/History/Vocabulary/Settings. Command–5 opens Snippets.

## Local data and permissions

Speech processing runs locally after installation. This source does not implement an audio/transcript upload service. The app requires microphone access and uses Accessibility for shortcuts and paste. Dependency and model downloads contact their providers during installation.

History defaults to enabled: up to 500 transcripts for 30 days at `~/Library/Application Support/Bucky/history.json`, with user-only permissions. It stores transcript text, time, duration and app name in local plain text. Disable saving in Settings to stop new entries; existing entries require deletion. Retention runs while Bucky is running.

Temporary audio is deleted after normal completion, cancellation and orderly quit. Crashes or forced termination may leave a temporary WAV. Deletion is not secure erasure. Clipboard managers and Universal Clipboard may handle copied text according to the installing Mac's settings.

The repository includes no recordings, personal transcripts, settings, runtime, model files or built app bundles. Generic macOS paths and the stable application identifier are code, not identifying device information. The GitHub hosting account remains visible; this distribution is not anonymous.

## Source and checks

- `Sources/`: native SwiftUI/AppKit app, local history and shortcuts.
- `worker.py` and `progressive.py`: local Parakeet MLX speech worker and verified in-memory reuse of completed windows.
- `scripts/install.sh` and `scripts/build.sh`: installation and native build.
- `tests/`: synthetic test code only, with no personal recordings or transcripts.

The build refuses to replace an existing app unless `BUCKY_REPLACE_APP=1` is explicit. Use a fresh `BUCKY_APP_PATH` for isolated validation. UI previews additionally require `BUCKY_UI_TESTING=1`; they use a separate bundle identifier and labelled synthetic data. Never install a preview as the production app. If Command Line Tools point at an incompatible SDK, use `SDKROOT` to select a compatible installed SDK before building.

Checks include native build/signature; text import, Unicode/whole-phrase expansion and snippet persistence; an isolated named pasteboard for clipboard races and rich-text preservation; history and shortcuts; and the simulated recording timer. Speech checks use synthetic audio with `tests/smoke.py`; `tests/progressive.py` compares growing-WAV results with batch processing, and `tests/progressive_safety.py` checks cancellation, identity and container handling. `tests/progressive.py --seconds 330 --realtime` writes a synthetic recording at recording speed for a long latency check. Synthetic checks do not establish real microphone, target-app paste, physical mouse or fresh-install behavior on a second Mac. This app is ad-hoc signed locally; it is not a notarized installer.

## Attribution

[NVIDIA Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), CC BY 4.0; [MLX conversion](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3), revision `ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15`; [Parakeet MLX](https://github.com/senstella/parakeet-mlx), Apache 2.0. Model SHA-256: `05e01c7f396c298cf7d23f61da7b504adeab698f0aaeafd9c82d198625464592`. Versions are in `requirements.lock.txt`; upstream licenses remain applicable to their components.
