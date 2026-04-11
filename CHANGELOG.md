# Changelog

All notable changes to ora are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release notes for a given version are extracted from this file by
`scripts/create-release.sh` and posted to the matching GitHub Release,
so keep each version section self-contained and user-facing.

## [Unreleased]

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
