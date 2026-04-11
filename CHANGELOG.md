# Changelog

All notable changes to ora are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release notes for a given version are extracted from this file by
`scripts/create-release.sh` and posted to the matching GitHub Release,
so keep each version section self-contained and user-facing.

## [Unreleased]

## [0.4] - 2026-04-11

### Added
- Cloud transcription providers. The OpenAI and Groq cards on the
  Models page are now live end-to-end: open the gear to paste an API
  key and model name (e.g. `gpt-4o-transcribe`, `whisper-large-v3`),
  select the card, and dictation routes to the provider instead of
  the local Parakeet model. Audio is encoded to AAC/m4a before upload
  so uploads stay small on slow networks.
- Toggle activation mode. Settings ▸ Dictation ▸ Input mode now
  actually flips behavior — "Toggle" means press once to start and
  press again to stop, while "Push to Talk" keeps the original
  hold-to-dictate behavior.

### Changed
- API keys now live in the login Keychain instead of plaintext
  UserDefaults. Existing installs are migrated automatically the
  first time you open an API provider's settings sheet, and the old
  UserDefaults copy is wiped. The settings sheet also gains an
  explicit Cancel / Done split, so edits only persist when you hit
  Done.
- App icon swapped to a minimal slash mark on a dark squircle.

## [0.3.1] - 2026-04-11

### Fixed
- App now displays as **Ora** (capitalized) in Finder, Dock, the menu
  bar, and the About window. The bundle identifier is unchanged, so
  existing installs upgrade in place.
- DMG installer now ships with a drag-to-Applications shortcut, so new
  users can install without opening a second Finder window. The release
  script requires `create-dmg` (`brew install create-dmg`) and will
  fail fast instead of silently falling back to a bare DMG.

## [0.3] - 2026-04-11

### Added
- Liquid Glass app icon (Icon Composer `.icon` bundle) so the app no
  longer renders inside the macOS 26 auto-applied white container, plus
  a custom menu bar template image in place of the waveform SF symbol.
- Provider brand icons on the Models page. Parakeet v2/v3 cards now
  show the NVIDIA mark, OpenAI API shows the OpenAI mark, and Groq API
  shows the Groq mark; cards without a brand asset fall back to the
  previous SF Symbol.

### Changed
- Menu bar dropdown is now Models / General / Dictation / Quit. The
  Input Source submenu, inline version label, and Check-for-Updates
  entry have moved into Settings where they belong, and menu items
  activate the app so Settings doesn't get hidden behind other windows.
- Input Source (now labeled "Microphone") and Notification Sound moved
  from General to the Dictation settings page — they only matter for
  transcription.
- Settings › General › Installed now shows the marketing version and
  git commit hash, generated at build time from the latest git tag.
  Debug builds render as `0.3-dev (abc1234)` so they're easy to tell
  apart from release builds.

## [0.2] - 2026-04-10

### Added
- Sparkle-powered automatic updates. The General settings page now
  includes a "Check for Updates…" button, and ora checks for updates
  in the background on launch.
- Input source selection. General settings now lets you pin a specific
  microphone for dictation, or follow the system default.
- Appearance preference (System / Light / Dark) and configurable
  notification sound, wired into the General settings page.
