# Ora

Local, private dictation for macOS. Press a hotkey, speak, release — your words are transcribed on-device and pasted into whatever app you're using.

Ora runs entirely on your Mac. Audio never leaves the device.

## Features

- **Global hotkey** (Option+Space) — hold to record, release to transcribe and paste
- **On-device transcription** — powered by Whisper models via [FluidAudio](https://github.com/FluidInference/FluidAudio), no network required
- **Works everywhere** — pastes into any app with a text field
- **Menu-bar app** — lives in your status bar, out of the way
- **Model management** — download and switch between Whisper model sizes from Settings

## Requirements

- macOS 26.2 or later
- Xcode 26+ (to build from source)
- Microphone permission
- Accessibility permission (for pasting into other apps)

## Getting started

No Apple Developer account required — the project uses ad-hoc signing (`Sign to Run Locally`) out of the box.

```bash
git clone https://github.com/KristampsWong/ora.git
cd ora
./scripts/dev-launch.sh
```

That's it. The script builds the project and launches Ora. On first launch, Ora walks you through granting Microphone and Accessibility permissions, and downloading a Whisper model.

### Dev scripts

| Script | Purpose |
|--------|---------|
| `scripts/dev-launch.sh` | Build and launch via Launch Services — permission prompts attribute to Ora correctly |
| `scripts/dev-run.sh` | Build and launch with stdout/stderr streaming to your terminal (useful for debugging) |
| `scripts/dev-reset.sh` | Wipe TCC entries and UserDefaults for a clean first-run experience |

### Custom code signing (optional)

Only needed if you want to sign with your own Apple Developer identity:

```bash
cp scripts/dev-env.local.sh.example scripts/dev-env.local.sh
# edit with your SIGN_IDENTITY and TEAM values
```

This file is gitignored and will never be committed.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
