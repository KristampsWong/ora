# Ora

A macOS menu-bar app for local, on-device voice dictation. Hold a hotkey, speak, release — your words are transcribed and pasted into the active application. No cloud, no API keys, everything runs on your Mac.

Powered by [FluidAudio](https://github.com/FluidInference/FluidAudio) and the Parakeet TDT 0.6B v3 speech model.

## Features

- **Hold-to-dictate** — configurable global hotkey (default: Right Command)
- **Fully local** — speech recognition runs on-device via CoreML, nothing leaves your Mac
- **Auto-paste** — transcribed text is inserted into whatever app has focus
- **Menu bar first** — lives in the menu bar, stays out of your way
- **Model management** — download and manage speech models from the Settings panel

## Requirements

- macOS 26.2+ (Sequoia)
- Xcode 26.2+

## Getting Started

1. **Clone the repo**

   ```bash
   git clone https://github.com/KristampsWong/ora.git
   cd ora
   ```

2. **Set your signing team**

   Open `ora.xcodeproj` in Xcode, select the **ora** target, go to **Signing & Capabilities**, and choose your development team. Xcode will resolve the signing identity automatically.

3. **Build and run**

   From Xcode: **Product > Run** (Cmd+R).

   Or from the terminal:

   ```bash
   # Build + launch via Launch Services (recommended — permissions
   # prompts attribute to ora, not Terminal)
   ./scripts/dev-launch.sh

   # Build + exec directly (stdout/stderr stream to terminal,
   # useful for debugging crashes)
   ./scripts/dev-run.sh
   ```

4. **Grant permissions**

   On first launch, Ora will ask for:
   - **Microphone** — for recording your voice
   - **Accessibility** — for pasting transcribed text into other apps

5. **Download a model**

   Open **Settings > Models** and download the Parakeet model. This is a one-time ~200 MB download.

6. **Dictate**

   Hold the hotkey (default: Right Command), speak, release. The transcribed text is pasted at your cursor.

## Dev Scripts

| Script | Purpose |
|---|---|
| `scripts/dev-run.sh` | Build and exec the binary directly. stdout/stderr stream to the terminal. Ctrl+C to quit. |
| `scripts/dev-launch.sh` | Build and open via Launch Services. Tails the system log. Use this to test permission flows. |
| `scripts/dev-reset.sh` | Wipe TCC entries and UserDefaults so the next launch behaves like a fresh install. |

## License

MIT
