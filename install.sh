#!/usr/bin/env bash
# jackpoint — one command, every AI coding CLI on your Mac.
# https://github.com/DareDev256/jackpoint   ·   MIT
#
#   curl -fsSL https://raw.githubusercontent.com/DareDev256/jackpoint/main/install.sh | bash
#
# Installs (idempotent, skips what's already there):
#   Claude Code · Gemini CLI · OpenAI Codex CLI · qwen-code · opencode
# Flags:
#   --local        also set up Ollama + a local model (free, offline, no account)
#   --uncensored   with --local, use an abliterated model (no refusals; your responsibility)
#   --minimal      only the two big ones: Gemini (free) + Claude Code
#   --help
#
# Written for bash 3.2 (macOS default). Read it before you run it. That's the deal.

set -uo pipefail

VERSION="1.0.2"
WANT_LOCAL=0; WANT_UNCENSORED=0; MINIMAL=0
for a in "$@"; do
  case "$a" in
    --local) WANT_LOCAL=1 ;;
    --uncensored) WANT_LOCAL=1; WANT_UNCENSORED=1 ;;
    --minimal) MINIMAL=1 ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next}{exit}' "$0" 2>/dev/null; exit 0 ;;
  esac
done

# === UI === ($'...' = real ESC bytes, so colors render in `cat` heredocs too, not just printf)
B=$'\033[1;36m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; R=$'\033[1;31m'; D=$'\033[2m'; X=$'\033[0m'
say()  { printf "%b\n" "$*"; }
step() { printf "\n${B}▸ %s${X}\n" "$*"; }
ok()   { printf "  ${G}✓${X} %s\n" "$*"; }
warn() { printf "  ${Y}!${X} %s\n" "$*"; }
err()  { printf "  ${R}✗${X} %s\n" "$*"; }

banner() {
cat <<'EOF'
   __            __                _       __
  /_/__ _____  / /__ ___  ___    (_)___  / /_
 / // _ `/ __/ /  '_// _ \/ _ \ / / _ \/ __/
/_/ \_,_/\__/ /_/\_\/ .__/\___//_/_//_/\__/
                   /_/
EOF
printf "  ${D}every AI coding CLI on your Mac · v%s${X}\n" "$VERSION"
}

# Results table (bash 3.2: parallel indexed arrays)
R_NAME=(); R_STATE=(); R_HOW=()
record() { R_NAME+=("$1"); R_STATE+=("$2"); R_HOW+=("$3"); }

# === Preflight ===
banner
step "Checking your Mac"
[ "$(uname -s)" = "Darwin" ] || { err "jackpoint is macOS only."; exit 1; }
SWVER="$(sw_vers -productVersion 2>/dev/null || echo '?')"
ok "macOS $SWVER on $(uname -m)"

# Internet / DNS preflight — the friendly version of the 'could not resolve host' wall.
if ! curl -fsS --max-time 8 -o /dev/null "https://claude.ai/install.sh" 2>/dev/null; then
  if ping -c1 -t3 1.1.1.1 >/dev/null 2>&1; then
    err "You're online but DNS can't resolve hostnames."
    say  "    Fix it, then re-run jackpoint:"
    say  "      ${B}networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8${X}"
    say  "      ${B}sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder${X}"
    say  "    If Tailscale is on: ${B}tailscale set --accept-dns=false${X}"
  else
    err "No internet. Connect to Wi-Fi (clear any login page), then re-run."
  fi
  exit 1
fi
ok "Internet + DNS working"

# Cache sudo once — Node's .pkg install needs it (Gemini + qwen both require Node).
say "\n  ${D}Your Mac password may be requested once (to install Node).${X}"
sudo -v 2>/dev/null || true

# === Logging: every install step is captured so failures are debuggable ===
LOG="$HOME/.jackpoint.log"
{ echo "jackpoint $VERSION — $(date '+%Y-%m-%d %H:%M:%S')"; echo "macOS $SWVER $(uname -m)"; } > "$LOG" 2>/dev/null || true
run() {  # run "<shell string>" — logs stdout+stderr to $LOG, returns the command's status
  echo "" >> "$LOG"; echo "### $1" >> "$LOG"
  bash -c "$1" >> "$LOG" 2>&1
}
have() { command -v "$1" >/dev/null 2>&1; }

# npm's default global prefix is root-owned (/usr/local) on a fresh Mac → `npm -g` = EACCES.
# Point it at a user-writable dir so installs need NO sudo and never hit permission errors.
NPM_GLOBAL="$HOME/.npm-global"
setup_npm_prefix() {
  mkdir -p "$NPM_GLOBAL/bin"
  export NPM_CONFIG_PREFIX="$NPM_GLOBAL"
  export PATH="$NPM_GLOBAL/bin:$PATH"   # callable in THIS run too
}

# === Node 22 (only because Gemini needs 20+ and qwen needs 22+) ===
ensure_node() {
  if command -v node >/dev/null 2>&1; then
    NMAJ="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    [ "${NMAJ:-0}" -ge 22 ] && { ok "node $(node -v)"; setup_npm_prefix; return 0; }
  fi
  step "Installing Node 22"
  if command -v brew >/dev/null 2>&1; then
    run "brew install node@22 && brew link --overwrite --force node@22" || true
  fi
  if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -lt 22 ]; then
    # Universal .pkg (node-vX.Y.Z.pkg — NO arch suffix; that was the 404 bug)
    LP="$(curl -fsSL --retry 2 --max-time 30 'https://nodejs.org/dist/latest-v22.x/' 2>/dev/null | grep -oE 'node-v22[0-9.]+\.pkg' | head -1 || true)"
    if [ -n "$LP" ]; then NURL="https://nodejs.org/dist/latest-v22.x/$LP"; else NURL="https://nodejs.org/dist/v22.14.0/node-v22.14.0.pkg"; fi
    run "curl -fsSL --retry 3 --max-time 300 -o /tmp/jp-node.pkg '$NURL'" || { err "Node download failed — see ~/.jackpoint.log"; return 1; }
    run "sudo installer -pkg /tmp/jp-node.pkg -target /" && rm -f /tmp/jp-node.pkg
  fi
  command -v node >/dev/null 2>&1 || { err "Node didn't land on PATH — see ~/.jackpoint.log"; return 1; }
  ok "node $(node -v)"; setup_npm_prefix
}

# === CLI installers (idempotent · logged · with fallbacks) ===

fail_row() { err "failed — run: tail -n 25 ~/.jackpoint.log"; record "$1" "fail" ""; }

install_claude() {
  step "Claude Code"
  if have claude || [ -x "$HOME/.local/bin/claude" ]; then ok "already installed"
  elif run "curl -fsSL https://claude.ai/install.sh | bash"; then ok "installed"
  else fail_row "Claude Code"; return; fi
  record "Claude Code" "ok" "claude   → sign in (needs Claude Pro/Max)"
}

install_gemini() {
  step "Gemini CLI"
  if have gemini; then ok "already installed"
  else
    ensure_node || { fail_row "Gemini CLI"; return; }
    if run "npm install -g @google/gemini-cli"; then ok "installed"
    elif command -v brew >/dev/null 2>&1 && run "brew install gemini-cli"; then ok "installed (brew)"
    else fail_row "Gemini CLI"; return; fi
  fi
  record "Gemini CLI" "ok" "gemini   → sign in with Google  (FREE tier)"
}

install_codex() {
  step "OpenAI Codex CLI"
  if have codex; then ok "already installed"
  elif run "CODEX_NON_INTERACTIVE=1 curl -fsSL https://chatgpt.com/codex/install.sh | sh"; then ok "installed"
  elif ensure_node && run "npm install -g @openai/codex"; then ok "installed (npm)"
  else fail_row "Codex CLI"; return; fi
  record "Codex CLI" "ok" "codex    → sign in with ChatGPT (paid plan)"
}

install_qwen() {
  step "qwen-code"
  if have qwen; then ok "already installed"
  else
    ensure_node || { fail_row "qwen-code"; return; }
    if run "npm install -g @qwen-code/qwen-code@latest"; then ok "installed"
    else fail_row "qwen-code"; return; fi
  fi
  if [ "$WANT_LOCAL" -eq 1 ]; then record "qwen-code" "ok" "qwen     → wired to your local model (offline)"
  else record "qwen-code" "ok" "qwen     → needs an API key, or run: jackpoint --local"; fi
}

install_opencode() {
  step "opencode"
  if have opencode; then ok "already installed"
  elif run "curl -fsSL https://opencode.ai/install | bash"; then ok "installed"
  else fail_row "opencode"; return; fi
  record "opencode" "ok" "opencode → /connect (use Claude Pro, or a local model)"
}

# === Optional: local offline model (Ollama) ===
pick_local_model() {
  MEM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
  if [ "$WANT_UNCENSORED" -eq 1 ]; then
    if   [ "$MEM_GB" -ge 60 ]; then echo "huihui_ai/qwen3.5-abliterated:35b"
    elif [ "$MEM_GB" -ge 30 ]; then echo "huihui_ai/qwen3.5-abliterated:27b"
    elif [ "$MEM_GB" -ge 22 ]; then echo "huihui_ai/qwen3-abliterated:14b"
    elif [ "$MEM_GB" -ge 14 ]; then echo "huihui_ai/qwen3.5-abliterated:9b"
    else                            echo "huihui_ai/qwen3-abliterated:4b"; fi
  else
    if   [ "$MEM_GB" -ge 30 ]; then echo "qwen3-coder:30b"
    elif [ "$MEM_GB" -ge 14 ]; then echo "qwen2.5-coder:7b"
    else                            echo "qwen2.5-coder:3b"; fi
  fi
}

install_local() {
  step "Local model (Ollama, offline)"
  if ! have ollama && [ ! -d /Applications/Ollama.app ]; then
    if command -v brew >/dev/null 2>&1; then brew install ollama >/dev/null 2>&1 || true; fi
    if ! have ollama && [ ! -d /Applications/Ollama.app ]; then
      curl -fsSL --retry 3 -o /tmp/jp-ollama.dmg "https://ollama.com/download/Ollama.dmg" || { err "Ollama download failed"; return; }
      MNT="$(hdiutil attach -nobrowse -noverify /tmp/jp-ollama.dmg 2>/dev/null | grep -oE '/Volumes/[^ ]+' | head -1)"
      [ -d "$MNT/Ollama.app" ] && sudo cp -R "$MNT/Ollama.app" /Applications/ 2>/dev/null
      hdiutil detach "$MNT" >/dev/null 2>&1 || true; rm -f /tmp/jp-ollama.dmg
    fi
  fi
  if ! have ollama && [ -x /Applications/Ollama.app/Contents/Resources/ollama ]; then
    sudo ln -sf /Applications/Ollama.app/Contents/Resources/ollama /usr/local/bin/ollama 2>/dev/null || true
  fi
  ok "Ollama installed"

  # qwen-code's big agent prompt truncates at Ollama's default 4K context → tool calls break.
  launchctl setenv OLLAMA_CONTEXT_LENGTH 65536 2>/dev/null || true
  open -a Ollama 2>/dev/null || true
  ( OLLAMA_CONTEXT_LENGTH=65536 ollama serve >/dev/null 2>&1 & ) 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do curl -fsS http://localhost:11434/api/version >/dev/null 2>&1 && break; sleep 1; done

  MODEL="$(pick_local_model)"
  step "Pulling $MODEL (one-time, multi-GB)"
  if ollama pull "$MODEL"; then ok "model ready"
  elif [ "$WANT_UNCENSORED" -eq 1 ] && ollama pull "huihui_ai/qwen3-abliterated:8b"; then
    MODEL="huihui_ai/qwen3-abliterated:8b"; ok "model ready (stable fallback)"
  else warn "pull failed — see ~/.jackpoint.log; retry: ollama pull $MODEL"; fi

  # Wire qwen-code → local Ollama (OpenAI-compatible, no key leaves the box)
  mkdir -p "$HOME/.qwen"
  printf 'OPENAI_API_KEY=ollama\nOPENAI_BASE_URL=http://localhost:11434/v1\nOPENAI_MODEL=%s\n' "$MODEL" > "$HOME/.qwen/.env"
  cat > "$HOME/.qwen/settings.json" <<JSON
{
  "modelProviders": { "openai": [ {
    "id": "${MODEL}", "name": "Local (Ollama)", "envKey": "OPENAI_API_KEY",
    "baseUrl": "http://localhost:11434/v1",
    "generationConfig": { "timeout": 600000, "contextWindowSize": 65536,
      "samplingParams": { "temperature": 0.7, "top_p": 0.8, "max_tokens": 32768 } } } ] },
  "security": { "auth": { "selectedType": "openai" } },
  "model": { "name": "${MODEL}" },
  "privacy": { "usageStatisticsEnabled": false }
}
JSON
  ok "qwen wired to local model: $MODEL"
  record "Ollama (local)" "ok" "ollama run $MODEL   → offline chat, no account"
}

# === Make every new command work in a fresh shell (the macOS PATH trap) ===
setup_path() {
  step "Wiring PATH"
  BLOCK_BEGIN="# >>> jackpoint PATH >>>"
  BLOCK_END="# <<< jackpoint PATH <<<"
  # $HOME (never ~ — tilde bug #6090). NPM_CONFIG_PREFIX keeps future `npm -g` user-writable too.
  L1="export NPM_CONFIG_PREFIX=\"\$HOME/.npm-global\""
  L2="export PATH=\"\$HOME/.local/bin:\$HOME/.npm-global/bin:\$PATH\""
  for rc in "$HOME/.zshrc" "$HOME/.zprofile"; do
    [ -f "$rc" ] && sed -i '' '/# >>> jackpoint PATH >>>/,/# <<< jackpoint PATH <<</d' "$rc" 2>/dev/null || true
    { echo ""; echo "$BLOCK_BEGIN"; echo "$L1"; echo "$L2"; echo "$BLOCK_END"; } >> "$rc"
  done
  ok "PATH set in ~/.zshrc and ~/.zprofile"
}

# === Friendly launchers ("hotkeys") + a 'jackpoint' cheatsheet command ===
write_launchers() {
  step "Shortcuts"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share"

  # Short aliases for the local model (beginners won't type 'ollama run <long-tag>')
  if [ "$WANT_LOCAL" -eq 1 ] && [ -n "${MODEL:-}" ]; then
    AB="# >>> jackpoint aliases >>>"; AE="# <<< jackpoint aliases <<<"
    ALIASES="alias chat=\"ollama run $MODEL\"
alias models=\"ollama list\""
    if [ "$WANT_UNCENSORED" -eq 1 ]; then
      ALIASES="$ALIASES
alias qwen-uc=\"ollama run $MODEL\""
    else
      ALIASES="$ALIASES
alias qwen-local=\"ollama run $MODEL\""
    fi
    for rc in "$HOME/.zshrc" "$HOME/.zprofile"; do
      [ -f "$rc" ] && sed -i '' '/# >>> jackpoint aliases >>>/,/# <<< jackpoint aliases <<</d' "$rc" 2>/dev/null || true
      { echo ""; echo "$AB"; echo "$ALIASES"; echo "$AE"; } >> "$rc"
    done
    if [ "$WANT_UNCENSORED" -eq 1 ]; then ok "shortcuts: chat · qwen-uc · models"
    else ok "shortcuts: chat · qwen-local · models"; fi
  fi

  # Build the cheatsheet text from what actually installed
  CARD="$HOME/.local/share/jackpoint-card.txt"
  {
    echo ""
    echo "  YOUR AI TOOLKIT — type any of these:"
    echo ""
    i=0
    while [ "$i" -lt "${#R_NAME[@]}" ]; do
      [ "${R_STATE[$i]}" = "ok" ] && [ -n "${R_HOW[$i]}" ] && printf "    %s\n" "${R_HOW[$i]}"
      i=$((i+1))
    done
    if [ "$WANT_LOCAL" -eq 1 ] && [ -n "${MODEL:-}" ]; then
      echo ""
      echo "    chat       → quick offline chat (no account, no internet)"
      [ "$WANT_UNCENSORED" -eq 1 ] && echo "    qwen-uc    → uncensored offline model" || echo "    qwen-local → offline model"
      echo "    models     → list your local models"
    fi
    echo ""
    echo "  Type 'jackpoint' anytime to see this again."
    echo ""
  } > "$CARD"

  # The 'jackpoint' command just prints the card
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$CARD" > "$HOME/.local/bin/jackpoint"
  chmod +x "$HOME/.local/bin/jackpoint"
  ok "type 'jackpoint' anytime to see your commands"
}

# === Run ===
if [ "$MINIMAL" -eq 1 ]; then
  install_gemini; install_claude
else
  install_claude; install_gemini; install_codex; install_qwen; install_opencode
fi
setup_path
[ "$WANT_LOCAL" -eq 1 ] && install_local
write_launchers

# === The card ===
say ""
printf "${G}┌──────────────────────────────────────────────────────────────┐${X}\n"
printf "${G}│  jackpoint complete — your AI toolkit                          │${X}\n"
printf "${G}└──────────────────────────────────────────────────────────────┘${X}\n"
i=0; FAILS=0
while [ "$i" -lt "${#R_NAME[@]}" ]; do
  if [ "${R_STATE[$i]}" = "ok" ]; then printf "  ${G}✓${X} %-14s ${D}%s${X}\n" "${R_NAME[$i]}" "${R_HOW[$i]}"
  else printf "  ${R}✗${X} %-14s ${D}failed${X}\n" "${R_NAME[$i]}"; FAILS=$((FAILS+1)); fi
  i=$((i+1))
done
if [ "$FAILS" -gt 0 ]; then
  printf "\n  ${Y}%d didn't install.${X} Why: ${B}tail -n 30 ~/.jackpoint.log${X}\n" "$FAILS"
  printf "  Re-run jackpoint to retry ONLY the failed ones.\n"
fi
cat <<EOF

  Your first commands:
      ${B}gemini${X}     ${D}# easiest start — free with a Google login${X}
      ${B}claude${X}     ${D}# if you have Claude Pro/Max${X}
      ${B}jackpoint${X}  ${D}# see your toolkit anytime${X}

  Star / issues: https://github.com/DareDev256/jackpoint
EOF

# Make the new PATH + shortcuts work RIGHT NOW — no "open a new window" step for beginners.
if [ -t 0 ] && [ -t 1 ]; then
  printf "\n${G}▸ Loading your commands…${X}  ${D}type 'gemini' to start, or 'exit' to close.${X}\n\n"
  exec zsh -il
else
  printf "\n${Y}Almost there:${X} open a new Terminal window (${B}Cmd+N${X}) so your commands load.\n"
fi
