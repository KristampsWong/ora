# Ora

[![Latest release](https://img.shields.io/github/v/release/KristampsWong/ora?display_name=tag&sort=semver)](https://github.com/KristampsWong/ora/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/KristampsWong/ora/total)](https://github.com/KristampsWong/ora/releases)
[![Stars](https://img.shields.io/github/stars/KristampsWong/ora?style=flat)](https://github.com/KristampsWong/ora/stargazers)
[![License](https://img.shields.io/github/license/KristampsWong/ora)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2026.2%2B-lightgrey)

Local, private dictation for macOS. Press a hotkey, speak, release — your words are transcribed on-device and pasted into whatever app you're using.

## Install

**[→ Download the latest release](https://github.com/KristampsWong/ora/releases/latest)**

1. Download `ora-x.y.z.dmg` from the latest release.
2. Open the DMG and drag **Ora** onto the Applications shortcut.
3. Launch Ora from Applications. On first launch it'll walk you through microphone + accessibility permissions and downloading a Whisper model.

Ora is signed with a Developer ID and notarized by Apple, so Gatekeeper will open it without warnings. Updates ship automatically via [Sparkle](https://sparkle-project.org) — once installed, new versions are fetched in the background and you're prompted to restart.

### Requirements

- macOS 26.2 (Tahoe) or later
- Microphone permission
- Accessibility permission (so Ora can paste into other apps)

Building from source additionally needs Xcode 26+ — see [Build from source](#build-from-source) below.

## Privacy

Ora is built around a simple rule: **your voice never leaves your Mac.**

- **No network calls for transcription.** Whisper models run entirely on-device via [FluidAudio](https://github.com/FluidInference/FluidAudio). Audio is captured, transcribed, and discarded locally.
- **No telemetry, no analytics, no crash reporting.** Ora does not phone home and has no server-side component. The only outbound network traffic is Sparkle checking GitHub for new release DMGs — and you can turn that off in Settings.
- **Models live in your own Application Support directory.** Download and delete them from Settings; nothing is hidden.
- **Open source under Apache 2.0.** Read the code, build it yourself, audit the network calls — the whole app is in this repo.

If you're dictating something sensitive and want belt-and-suspenders confirmation, throw Ora into Little Snitch or disconnect Wi-Fi: transcription will keep working exactly the same.

## Features

- **Global hotkey** (Option+Space) — hold to record, release to transcribe and paste
- **On-device transcription** — multiple Whisper-family models via FluidAudio, switchable from Settings
- **Works everywhere** — pastes into any app with a text field
- **Menu-bar app** — lives in your status bar, out of the way
- **Auto-updates** — signed, notarized releases via Sparkle

## Build from source

No Apple Developer account required — the project uses ad-hoc signing (`Sign to Run Locally`) out of the box.

```bash
git clone https://github.com/KristampsWong/ora.git
cd ora
./scripts/dev-launch.sh
```

The script builds the project and launches Ora via Launch Services, so permission prompts attribute to Ora correctly.

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
