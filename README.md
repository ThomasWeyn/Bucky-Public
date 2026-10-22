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

Keep the source folder in place: the app runs its engine from that folder. After moving it, quit Bucky and run `bash scripts/build.sh` again. macOS may require renewed permissions after rebuilding. The build records the path of the clone on the installing Mac in the locally built app; no prebuilt app or originating device path is distributed here. Each Mac has its own settings and history.

## Build troubleshooting

If the compiler reports `SwiftUIMacros.StateMacro` missing, the selected Apple SDK and available compiler plug-ins do not match. Use compatible Apple Command Line Tools or Xcode. With the macOS 26.5 SDK already installed, this snapshot builds with:

```sh
SDKROOT="$(xcrun --sdk macosx26.5 --show-sdk-path)" bash scripts/install.sh
```

This selects an installed SDK for this command; it does not change the system toolchain. Snapshot build/signature checks used that SDK with Apple Swift 6.4. A fresh dependency installation on another physical Mac remains unverified.

## Use

- **Dictate:** click the microphone or use your shortcut. Press again to finish. There is no automatic recording time limit. Escape, quitting and sleep cancel recording.
- **History:** search, read, copy or delete transcripts. Individual deletion has Undo; deleting all requires confirmation.
- **Vocabulary:** add one `heard words = preferred spelling` replacement per line. The public default contains only `super whisper = Superwhisper`.
- **Settings:** permissions, keyboard/mouse shortcuts, hold-to-talk, recording sounds, startup at login, automatic paste and history controls.

The default shortcut is Control-Space; Control-Option-Space is a backup. A recorded user shortcut takes precedence. Side and middle mouse buttons can be captured; primary and secondary clicks are excluded. Quit another dictation app using the same shortcut before testing.

Automatic paste targets the original app only if it remains foreground. Bucky never presses Return. Changing fields within that app changes the paste destination. Otherwise, paste from the clipboard manually. An emitted paste keystroke does not guarantee insertion.

## Local data and permissions

Speech processing runs locally after installation. This source does not implement an audio/transcript upload service. The app requires microphone access and uses Accessibility for shortcuts and paste. Dependency and model downloads contact their providers during installation.

History defaults to enabled: up to 500 transcripts for 30 days at `~/Library/Application Support/Bucky/history.json`, with user-only permissions. It stores transcript text, time, duration and app name in local plain text. Disable saving in Settings to stop new entries; existing entries require deletion. Retention runs while Bucky is running.

Temporary audio is deleted after normal completion, cancellation and orderly quit. Crashes or forced termination may leave a temporary WAV. Deletion is not secure erasure. Clipboard managers and Universal Clipboard may handle copied text according to the installing Mac's settings.

The repository includes no recordings, personal transcripts, settings, runtime, model files or built app bundles. Generic macOS paths and the stable application identifier are code, not identifying device information. The GitHub hosting account remains visible; this distribution is not anonymous.

## Source and checks

- `Sources/`: native SwiftUI/AppKit app, local history and shortcuts.
- `worker.py`: local Parakeet MLX speech worker over stdio.
- `scripts/install.sh` and `scripts/build.sh`: installation and native build.
- `tests/`: synthetic test code only, with no personal recordings or transcripts.

Native build/signature and focused history, shortcut and simulated recording-timer checks are performed for this snapshot. Synthetic checks do not establish real microphone, target-app paste, physical mouse or fresh-install behavior on a second Mac. This app is ad-hoc signed locally; it is not a notarized installer.

## Attribution

[NVIDIA Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), CC BY 4.0; [MLX conversion](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3), revision `ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15`; [Parakeet MLX](https://github.com/senstella/parakeet-mlx), Apache 2.0. Model SHA-256: `05e01c7f396c298cf7d23f61da7b504adeab698f0aaeafd9c82d198625464592`. Versions are in `requirements.lock.txt`; upstream licenses remain applicable to their components.
