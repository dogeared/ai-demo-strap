#!/usr/bin/env bash
#
# bootstrap.sh — Set up a fresh macOS laptop for AI vibe-coding events.
#
# Installs Homebrew, common dev tools, and AI coding assistants (Cursor,
# Windsurf, Claude Code, Gemini CLI, OpenAI Codex CLI, etc.). After install,
# optionally walks the user through authenticating each tool.
#
# Usage:
#   ./bootstrap.sh              install everything (default)
#   ./bootstrap.sh --uninstall  remove everything this script installed
#   ./bootstrap.sh --help       show this help
#
# Safe to re-run: every step checks for existing state before acting.

set -u
set -o pipefail

# ---------- pretty output ----------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

log()   { printf "%s==>%s %s\n" "$BLUE$BOLD" "$RESET" "$*"; }
ok()    { printf "%s ✓%s %s\n"  "$GREEN"     "$RESET" "$*"; }
warn()  { printf "%s ⚠%s  %s\n" "$YELLOW"    "$RESET" "$*"; }
err()   { printf "%s ✗%s %s\n"  "$RED"       "$RESET" "$*" >&2; }
step()  { printf "\n%s── %s ──%s\n" "$CYAN$BOLD" "$*" "$RESET"; }

ask_yn() {
  # ask_yn "Question?" [default y|n]  -> returns 0 for yes, 1 for no
  local prompt="$1" default="${2:-n}" reply
  local hint="[y/N]"; [[ "$default" == "y" ]] && hint="[Y/n]"
  while true; do
    printf "%s %s %s " "$BOLD?$RESET" "$prompt" "$hint"
    read -r reply </dev/tty || reply=""
    [[ -z "$reply" ]] && reply="$default"
    case "$reply" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO)   return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

# ---------- shared tool lists (used by both install and uninstall) ----------
# Everything that can come from Homebrew, does. Only Claude Code and OpenAI
# Codex have no brew formula as of this writing — those stay on npm.
FORMULAE=(
  # general dev prerequisites
  git
  node          # required for Claude Code + OpenAI Codex CLIs
  python        # often needed by AI tooling
  gh            # GitHub CLI
  jq            # JSON wrangling — useful in demos
  ripgrep       # fast search, used by many AI tools
  wget
  # AI CLIs available in homebrew-core
  gemini-cli    # Google's official Gemini CLI
  ollama        # local LLM runtime (pairs with ollama-app)
  aider         # AI pair-programmer
  llm           # Simon Willison's general-purpose AI CLI
)

CASKS=(
  # AI-first editors / IDEs
  cursor                # AI-first editor
  windsurf              # Codeium's AI IDE
  visual-studio-code    # the fallback everyone knows
  zed                   # fast, AI-native editor
  # AI desktop assistants (official vendor apps)
  claude                # Anthropic Claude desktop
  chatgpt               # OpenAI ChatGPT desktop
  codex-app             # OpenAI Codex desktop (manages coding agents)
  google-gemini         # Google Gemini desktop
  # Local-model AI desktops
  ollama-app            # Ollama desktop UI
  lm-studio             # Discover/run local LLMs
  msty                  # Run LLMs locally
  jan                   # Offline AI chat
  cherry-studio         # Multi-provider LLM client
  # Terminals & browser
  warp                  # AI-native terminal
  iterm2                # classic terminal
  ghostty               # modern GPU terminal
  google-chrome         # for OAuth flows + general demo use
  # CLI binaries distributed as casks (not GUI apps — go on PATH)
  codex                 # OpenAI Codex CLI (brew binary distribution)
)

# Only tools without a brew package. Kept tiny on purpose.
NPM_PACKAGES=(
  "@anthropic-ai/claude-code"
)

# ---------- arg parsing ----------
usage() {
  cat <<EOF
${BOLD}bootstrap.sh${RESET} — AI vibe-coding event laptop bootstrapper

${BOLD}Usage:${RESET}
  ./bootstrap.sh              Install everything (default)
  ./bootstrap.sh --uninstall  Remove tools this script installed
  ./bootstrap.sh -h | --help  Show this help

The uninstaller never removes Xcode Command Line Tools, and prompts
before removing Homebrew itself or wiping per-tool user config.
EOF
}

MODE="install"
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --uninstall) MODE="uninstall"; shift ;;
    -h|--help)   usage; exit 0 ;;
    "")          shift ;;
    *)           err "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ---------- uninstall ----------
do_uninstall() {
  step "Uninstall mode"
  printf "%sThis will remove tools installed by this script:%s\n" "$BOLD" "$RESET"
  printf "  %sFormulae:%s %s\n" "$DIM" "$RESET" "${FORMULAE[*]}"
  printf "  %sCasks:%s    %s\n" "$DIM" "$RESET" "${CASKS[*]}"
  printf "  %snpm pkgs:%s %s\n" "$DIM" "$RESET" "${NPM_PACKAGES[*]}"
  printf "  %s(Xcode CLI Tools will be left alone.)%s\n" "$DIM" "$RESET"
  if ! ask_yn "Continue?" "n"; then
    log "Aborted."
    exit 0
  fi

  # npm packages first (so node can be removed cleanly afterward)
  if command -v npm >/dev/null 2>&1; then
    step "Removing npm-based AI CLIs"
    for pkg in "${NPM_PACKAGES[@]}"; do
      if npm list -g --depth=0 "$pkg" >/dev/null 2>&1; then
        log "npm uninstall -g $pkg"
        npm uninstall -g "$pkg" >/dev/null 2>&1 && ok "$pkg removed" \
          || warn "Failed to remove $pkg"
      else
        ok "$pkg not installed"
      fi
    done
  else
    warn "npm not found — skipping npm-based tools."
  fi

  if command -v brew >/dev/null 2>&1; then
    step "Removing GUI apps (casks)"
    for cask in "${CASKS[@]}"; do
      if brew list --cask "$cask" >/dev/null 2>&1; then
        log "brew uninstall --cask $cask"
        brew uninstall --cask "$cask" >/dev/null 2>&1 && ok "$cask removed" \
          || warn "Failed to remove $cask"
      else
        ok "$cask not installed via brew"
      fi
    done

    step "Removing CLI formulae"
    # Reverse order so leaf packages come off before things they depend on.
    for (( i=${#FORMULAE[@]}-1 ; i>=0 ; i-- )); do
      pkg="${FORMULAE[$i]}"
      if brew list --formula "$pkg" >/dev/null 2>&1; then
        log "brew uninstall $pkg"
        if brew uninstall "$pkg" >/dev/null 2>&1; then
          ok "$pkg removed"
        else
          warn "$pkg has dependents — leaving in place. Run 'brew uses --installed $pkg' to investigate."
        fi
      else
        ok "$pkg not installed via brew"
      fi
    done

    log "brew autoremove (clean up orphaned deps)..."
    brew autoremove >/dev/null 2>&1 || true
  else
    warn "Homebrew not found — skipping brew packages."
  fi

  # User config / credentials — opt-in because this wipes sign-ins.
  step "User config & credentials"
  if ask_yn "Wipe per-tool config & credentials (recommended between events)?" "y"; then
    DIRS=(
      "$HOME/.npm-global"
      "$HOME/.claude"
      "$HOME/.gemini"
      "$HOME/.codex"
      "$HOME/.config/gh"
      "$HOME/Library/Application Support/Cursor"
      "$HOME/Library/Application Support/Windsurf"
      "$HOME/Library/Application Support/Code"
      "$HOME/Library/Application Support/Zed"
      "$HOME/Library/Application Support/dev.warp.Warp-Stable"
    )
    for d in "${DIRS[@]}"; do
      if [[ -e "$d" ]]; then
        rm -rf "$d" && ok "Removed $d" || warn "Could not remove $d"
      fi
    done
  else
    printf "  %sLeaving config dirs in place.%s\n" "$DIM" "$RESET"
  fi

  # ~/.zprofile cleanup
  ZPROFILE="$HOME/.zprofile"
  if [[ -f "$ZPROFILE" ]] && grep -qsE 'brew shellenv|\.npm-global/bin' "$ZPROFILE"; then
    if ask_yn "Remove brew/npm PATH lines this script added to ~/.zprofile?" "y"; then
      tmp="$(mktemp)"
      grep -vE 'brew shellenv|\.npm-global/bin' "$ZPROFILE" > "$tmp" \
        && mv "$tmp" "$ZPROFILE" \
        && ok "Cleaned ~/.zprofile"
    fi
  fi

  # Reset the npm prefix we set during install.
  if command -v npm >/dev/null 2>&1; then
    if [[ "$(npm config get prefix 2>/dev/null)" == "$HOME/.npm-global" ]]; then
      npm config delete prefix >/dev/null 2>&1 && ok "Reset npm global prefix"
    fi
  fi

  # Homebrew itself — strictly opt-in.
  if command -v brew >/dev/null 2>&1; then
    if ask_yn "Uninstall Homebrew itself? (destructive, removes /opt/homebrew or /usr/local/Homebrew)" "n"; then
      uninstaller="$(mktemp -t brew-uninstall)"
      trap 'rm -f "$uninstaller"' EXIT
      log "Downloading Homebrew uninstaller..."
      if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh \
            -o "$uninstaller" || [[ ! -s "$uninstaller" ]]; then
        err "Failed to download Homebrew uninstaller. Skipping."
      else
        printf "\n%sHomebrew uninstall needs sudo.%s Enter your password if prompted:\n" \
          "$BOLD$YELLOW" "$RESET"
        if ! sudo -v; then
          err "sudo authentication failed. Skipping Homebrew uninstall."
        else
          ( while true; do sudo -n true 2>/dev/null || exit; sleep 60; done ) &
          un_keepalive=$!
          log "Running official Homebrew uninstaller..."
          NONINTERACTIVE=1 /bin/bash "$uninstaller" || \
            warn "Uninstaller exited non-zero."
          kill "$un_keepalive" 2>/dev/null || true
        fi
      fi
    fi
  fi

  printf "\n%sUninstall complete.%s Xcode CLI Tools were left in place.\n" \
    "$BOLD$GREEN" "$RESET"
  exit 0
}

if [[ "$MODE" == "uninstall" ]]; then
  do_uninstall
fi

# ---------- preflight ----------
step "Preflight checks"

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This script only runs on macOS."
  exit 1
fi
ok "macOS detected ($(sw_vers -productVersion))"

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"
  ok "Apple Silicon (arm64)"
else
  BREW_PREFIX="/usr/local"
  ok "Intel (x86_64)"
fi

if [[ "$(id -u)" -eq 0 ]]; then
  err "Do not run this script as root. It will sudo when needed."
  exit 1
fi

# ---------- xcode command line tools ----------
step "Xcode Command Line Tools"

if xcode-select -p >/dev/null 2>&1; then
  ok "Already installed at $(xcode-select -p)"
else
  log "Installing Xcode Command Line Tools (a GUI prompt will appear)..."
  xcode-select --install || true
  warn "Complete the GUI install, then press Enter to continue."
  read -r _ </dev/tty || true
  if ! xcode-select -p >/dev/null 2>&1; then
    err "Xcode Command Line Tools still not detected. Aborting."
    exit 1
  fi
  ok "Installed."
fi

# ---------- homebrew ----------
step "Homebrew"

if command -v brew >/dev/null 2>&1; then
  ok "Already installed ($(brew --version | head -n1))"
else
  # Sanity-check HTTPS first. On fresh macOS VMs the system clock is often
  # months in the past, which makes recent TLS certs look "not yet valid"
  # and curl reports it as "unable to get local issuer certificate".
  BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  log "Verifying HTTPS connectivity to github.com..."
  if ! curl_err="$(curl -fsSL --max-time 15 -o /dev/null "$BREW_INSTALL_URL" 2>&1)"; then
    err "HTTPS check failed."
    printf "  %scurl: %s%s\n" "$DIM" "$curl_err" "$RESET"
    printf "  %ssystem date: %s%s\n" "$DIM" "$(date)" "$RESET"
    if printf '%s' "$curl_err" | grep -qiE 'ssl|certificate|tls'; then
      printf "\n%sLooks like a TLS/cert error.%s On a fresh macOS install\n" "$YELLOW$BOLD" "$RESET"
      printf "(especially in a UTM/QEMU VM) this almost always means the\n"
      printf "system clock is wrong — recent TLS certs appear 'not yet valid'.\n\n"
      printf "Fix the clock, then re-run this script:\n"
      printf "  %ssudo sntp -sS time.apple.com%s\n\n" "$BOLD" "$RESET"
      printf "Or: %sSystem Settings → General → Date & Time%s → toggle 'Set automatically'.\n" "$BOLD" "$RESET"
    else
      printf "\nCheck network, DNS, and proxy settings, then re-run.\n"
    fi
    exit 1
  fi
  ok "HTTPS connectivity OK"

  # Download installer to a file so curl errors are actually caught — a
  # 'bash -c "$(curl ...)"' silently runs an empty script if curl fails.
  installer="$(mktemp -t brew-install)"
  trap 'rm -f "$installer"' EXIT
  log "Downloading Homebrew installer..."
  if ! curl -fsSL "$BREW_INSTALL_URL" -o "$installer" || [[ ! -s "$installer" ]]; then
    err "Failed to download Homebrew installer."
    exit 1
  fi

  # Pre-authenticate sudo. NONINTERACTIVE=1 makes brew use `sudo -n`, which
  # requires either passwordless sudo OR a cached sudo credential. macOS
  # admins are NOT passwordless by default — so we prompt once here and
  # cache. (Without this, an admin user still gets "Need sudo access".)
  printf "\n%sHomebrew needs sudo for initial setup.%s Enter your password if prompted:\n" \
    "$BOLD$YELLOW" "$RESET"
  if ! sudo -v; then
    err "sudo authentication failed. Is your user an admin? Aborting."
    exit 1
  fi
  # Keep the sudo timestamp fresh while the installer runs (it can take
  # several minutes, longer than the default 5-min timeout).
  ( while true; do sudo -n true 2>/dev/null || exit; sleep 60; done ) &
  sudo_keepalive=$!
  trap 'kill "$sudo_keepalive" 2>/dev/null; rm -f "$installer"' EXIT

  log "Running Homebrew installer..."
  if ! NONINTERACTIVE=1 /bin/bash "$installer"; then
    kill "$sudo_keepalive" 2>/dev/null || true
    err "Homebrew installer exited non-zero."
    err "If it complained about sudo, re-run the script."
    exit 1
  fi
  kill "$sudo_keepalive" 2>/dev/null || true

  if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
    err "Installer finished but $BREW_PREFIX/bin/brew is missing."
    err "Something went wrong silently — check the installer output above."
    exit 1
  fi

  # Make brew available in this shell for the rest of the script.
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  # And persist for future shells (zsh is macOS default).
  ZPROFILE="$HOME/.zprofile"
  if ! grep -qs "brew shellenv" "$ZPROFILE" 2>/dev/null; then
    printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >>"$ZPROFILE"
    ok "Added brew shellenv to $ZPROFILE"
  fi
  ok "Homebrew installed."
fi

if ! command -v brew >/dev/null 2>&1; then
  err "brew is not on PATH after install. Aborting."
  err "Try opening a new terminal and running the script again."
  exit 1
fi

log "Updating Homebrew..."
if ! brew update >/dev/null; then
  err "brew update failed. Common cause: system clock skew or no network."
  err "Try: sudo sntp -sS time.apple.com  then re-run."
  exit 1
fi
ok "Homebrew up to date."

# ---------- brew packages ----------
step "Installing CLI formulae"
for pkg in "${FORMULAE[@]}"; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    log "Installing $pkg..."
    if brew install "$pkg"; then
      ok "$pkg installed"
    else
      warn "Failed to install $pkg — continuing."
    fi
  fi
done

step "Installing GUI apps (casks)"
for cask in "${CASKS[@]}"; do
  if brew list --cask "$cask" >/dev/null 2>&1; then
    ok "$cask already installed"
    continue
  fi
  # Detect apps installed outside of brew (e.g., dragged from a .dmg).
  app_name=""
  case "$cask" in
    cursor)             app_name="Cursor.app" ;;
    windsurf)           app_name="Windsurf.app" ;;
    visual-studio-code) app_name="Visual Studio Code.app" ;;
    zed)                app_name="Zed.app" ;;
    claude)             app_name="Claude.app" ;;
    chatgpt)            app_name="ChatGPT.app" ;;
    codex-app)          app_name="Codex.app" ;;
    google-gemini)      app_name="Gemini.app" ;;
    ollama-app)         app_name="Ollama.app" ;;
    lm-studio)          app_name="LM Studio.app" ;;
    msty)               app_name="Msty.app" ;;
    jan)                app_name="Jan.app" ;;
    cherry-studio)      app_name="Cherry Studio.app" ;;
    warp)               app_name="Warp.app" ;;
    iterm2)             app_name="iTerm.app" ;;
    google-chrome)      app_name="Google Chrome.app" ;;
    ghostty)            app_name="Ghostty.app" ;;
  esac
  if [[ -n "$app_name" && -d "/Applications/$app_name" ]]; then
    ok "$cask already present at /Applications/$app_name (skipping)"
    continue
  fi
  log "Installing $cask..."
  if brew install --cask "$cask"; then
    ok "$cask installed"
  else
    warn "Failed to install $cask — continuing."
  fi
done

# ---------- npm-based AI CLIs ----------
step "AI CLIs via npm"

if ! command -v npm >/dev/null 2>&1; then
  err "npm not found — node install must have failed. Skipping npm-based tools."
else
  # Make `npm install -g` work without sudo by pointing global prefix at $HOME.
  NPM_PREFIX="$HOME/.npm-global"
  if [[ "$(npm config get prefix)" != "$NPM_PREFIX" ]]; then
    mkdir -p "$NPM_PREFIX"
    npm config set prefix "$NPM_PREFIX"
    ok "Set npm global prefix to $NPM_PREFIX"
  fi
  # Make sure it's on PATH for this script and future shells.
  case ":$PATH:" in
    *":$NPM_PREFIX/bin:"*) ;;
    *) export PATH="$NPM_PREFIX/bin:$PATH" ;;
  esac
  ZPROFILE="$HOME/.zprofile"
  if ! grep -qs ".npm-global/bin" "$ZPROFILE" 2>/dev/null; then
    printf '\nexport PATH="$HOME/.npm-global/bin:$PATH"\n' >>"$ZPROFILE"
    ok "Added $NPM_PREFIX/bin to PATH in $ZPROFILE"
  fi

  # name:cmd:package triples — only tools without a brew package live here.
  NPM_TOOLS=(
    "Claude Code:claude:@anthropic-ai/claude-code"
  )
  for entry in "${NPM_TOOLS[@]}"; do
    name="${entry%%:*}"; rest="${entry#*:}"
    cmd="${rest%%:*}";   pkg="${rest#*:}"
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "$name already installed ($(command -v "$cmd"))"
    else
      log "Installing $name ($pkg)..."
      if npm install -g "$pkg"; then
        ok "$name installed"
      else
        warn "Failed to install $name — continuing."
      fi
    fi
  done
fi

# ---------- summary ----------
step "Install summary"
printf "%sInstalled CLIs:%s\n" "$BOLD" "$RESET"
for cmd in brew git node npm python3 gh jq rg \
           claude gemini codex ollama aider llm; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  %s✓%s %-8s %s%s%s\n" "$GREEN" "$RESET" "$cmd" "$DIM" "$(command -v "$cmd")" "$RESET"
  else
    printf "  %s✗%s %-8s %s(not on PATH)%s\n" "$RED" "$RESET" "$cmd" "$DIM" "$RESET"
  fi
done
printf "\n%sGUI apps in /Applications:%s\n" "$BOLD" "$RESET"
for app in "Cursor.app" "Windsurf.app" "Visual Studio Code.app" "Zed.app" \
           "Claude.app" "ChatGPT.app" "Codex.app" "Gemini.app" \
           "Ollama.app" "LM Studio.app" "Msty.app" "Jan.app" "Cherry Studio.app" \
           "Warp.app" "iTerm.app" "Ghostty.app" "Google Chrome.app"; do
  if [[ -d "/Applications/$app" ]]; then
    printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$app"
  else
    printf "  %s✗%s %s %s(missing)%s\n" "$RED" "$RESET" "$app" "$DIM" "$RESET"
  fi
done

# ---------- authentication ----------
step "Authentication"

if ! ask_yn "Walk through authenticating each tool now?" "y"; then
  printf "\n%sSkipping authentication. You can run each tool later to sign in.%s\n" "$DIM" "$RESET"
  printf "%sDone.%s Open a new terminal so PATH updates take effect.\n" "$BOLD$GREEN" "$RESET"
  exit 0
fi

# Each entry: "Display Name|prompt note|command to run"
# Commands that open GUI apps use `open -a` and return immediately; CLIs run
# in the foreground so the user can complete their flow before continuing.
# Auth entries are "name|note|cmd".
# Three command shapes drive the dispatch:
#   open -a <App>     → GUI app launch + wait
#   @newtab:<cli>     → open in a fresh Terminal.app window + wait
#                       (used for TUI CLIs that hang/crash in iTerm2/UTM)
#   <cli ...>         → run inline in the current terminal
AUTH_TOOLS=(
  # Browser-flow CLIs — short-lived in the terminal, run inline.
  "GitHub CLI|Will open a browser to sign in to github.com.|gh auth login --web"
  "Gemini CLI|Launches Gemini CLI. Follow the OAuth prompt, then exit when done.|gemini"
  # TUI CLIs — open in a fresh Terminal.app window (more reliable in UTM).
  "Claude Code|A new Terminal window will open. Pick a theme, type /login, complete browser auth, then close that window.|@newtab:claude"
  "OpenAI Codex CLI|A new Terminal window will open. Run /login (or follow the prompt), then close that window.|@newtab:codex"
  # AI-first editors.
  "Cursor|Opens Cursor. Sign in via Settings → Account, then return here.|open -a Cursor"
  "Windsurf|Opens Windsurf. Sign in via the welcome screen, then return here.|open -a Windsurf"
  # Vendor desktop assistants.
  "Claude (desktop)|Opens Claude. Sign in with your Anthropic account, then return here.|open -a Claude"
  "ChatGPT (desktop)|Opens ChatGPT. Sign in with your OpenAI account, then return here.|open -a ChatGPT"
  "Codex (desktop)|Opens Codex. Sign in with your OpenAI account, then return here.|open -a Codex"
  "Google Gemini (desktop)|Opens Gemini. Sign in with your Google account, then return here.|open -a Gemini"
)

for entry in "${AUTH_TOOLS[@]}"; do
  IFS='|' read -r name note cmd <<<"$entry"
  printf "\n%s%s%s\n" "$BOLD$CYAN" "$name" "$RESET"
  printf "  %s%s%s\n" "$DIM" "$note" "$RESET"

  # Decide dispatch mode and find the underlying command for the PATH check.
  if [[ "$cmd" == @newtab:* ]]; then
    mode="newtab"
    actual_cmd="${cmd#@newtab:}"
    check_token="${actual_cmd%% *}"
  elif [[ "${cmd%% *}" == "open" ]]; then
    mode="app"
    actual_cmd="$cmd"
    check_token="open"
  else
    mode="cli"
    actual_cmd="$cmd"
    check_token="${cmd%% *}"
  fi

  if [[ "$check_token" != "open" ]] && ! command -v "$check_token" >/dev/null 2>&1; then
    warn "$check_token not found — skipping $name."
    continue
  fi

  if ! ask_yn "Authenticate $name now?" "y"; then
    printf "  %sskipped.%s\n" "$DIM" "$RESET"
    continue
  fi

  case "$mode" in
    cli)
      eval "$actual_cmd" </dev/tty || warn "$name exited non-zero."
      ;;
    app)
      eval "$actual_cmd" || warn "Failed to launch $name."
      printf "  %sPress Enter once you've finished signing in to %s...%s " \
        "$DIM" "$name" "$RESET"
      read -r _ </dev/tty || true
      ;;
    newtab)
      # Open in a fresh Terminal.app window. This works around TUI/UTM
      # issues where Claude Code / Codex CLI hang or panic inside iTerm2.
      if osascript -e "tell application \"Terminal\" to do script \"$actual_cmd\"" >/dev/null 2>&1; then
        printf "  %sNew Terminal.app window opened — complete sign-in there, then close it.%s\n" \
          "$DIM" "$RESET"
      else
        warn "Couldn't open a new Terminal.app window. Run this manually:"
        printf "    %s%s%s\n" "$BOLD" "$actual_cmd" "$RESET"
      fi
      printf "  %sPress Enter once you've finished signing in to %s (or to skip)...%s " \
        "$DIM" "$name" "$RESET"
      read -r _ </dev/tty || true
      ;;
  esac
  ok "$name done."
done

printf "\n%sAll done.%s Open a new terminal so PATH changes take effect.\n" \
  "$BOLD$GREEN" "$RESET"
