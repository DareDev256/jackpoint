# Changelog

## 1.1.0 — 2026-09-01

### Added
- **Power guide** (`assets/power-guide.html` + PDF) — which CLI to reach for and what each one is actually good at.
- **Privacy guide** (`assets/privacy-guide.html` + PDF) — what leaves the machine, what never does, and how to run fully offline.
- A **Guides** section in the README linking all three guides. Nothing linked them before — including the quick start that shipped in 1.0.2. The docs existed; no path led to them.

### Fixed
- Both new guides shipped with no `<title>` element, rendering as an untitled browser tab, and with no `lang` attribute on `<html>`. Added both, matching the quick start.

## 1.0.2 — 2026-05-31

First public release. One command installs every AI coding CLI on macOS.

### Added
- One-command installer for Claude Code, Gemini CLI, OpenAI Codex CLI, qwen-code, and opencode.
- `--local` flag: installs Ollama plus a coding model sized to the Mac's RAM (offline, no account).
- `--uncensored` flag: uses an abliterated local model (implies `--local`).
- `--minimal` flag: Gemini (free) + Claude Code only.
- `jackpoint` cheatsheet command — prints your toolkit any time.
- `chat`, `qwen-uc`, `models` shortcuts for the local model.
- Full log at `~/.jackpoint.log`; re-running retries only what failed.
- 9-page designed quick-start PDF for first-time terminal users.

### Reliability (hardened against a real fresh-Mac field test)
- Node installed via the universal macOS `.pkg` (no arch-suffix 404).
- npm globals install to a user-writable prefix (`~/.npm-global`) — no `sudo`, no EACCES.
- Codex installs non-interactively with an npm fallback.
- Internet/DNS preflight with a clear fix message.
- Drops into a fresh shell at the end so new commands work immediately.
- bash 3.2 compatible (macOS default shell).

[1.0.2]: https://github.com/DareDev256/jackpoint
