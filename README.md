# ai-demo-strap

One-shot bootstrap for fresh macOS laptops used at AI vibe-coding events.
Installs editors, terminals, AI assistants (desktop + CLI), and common dev
tooling in a single pass, then optionally walks through signing in to each
tool.

Safe to re-run: every step checks for existing state before acting.

---

## What it installs

Everything that can come from Homebrew, does. Two AI CLIs without a brew
formula come from npm.

**Editors / IDEs** (cask): Cursor, Windsurf, VS Code, Zed

**AI desktop assistants** (cask): Claude, ChatGPT, Codex, Google Gemini

**Local-model desktops** (cask): Ollama, LM Studio, Msty, Jan, Cherry Studio

**Terminals & browser** (cask): Warp, iTerm2, Ghostty, Google Chrome

**AI CLIs** (formula): `gemini-cli`, `ollama`, `aider`, `llm`

**AI CLI** (cask, binary distribution): `codex` — OpenAI's Codex CLI ships
as a release binary via Homebrew's cask channel, not a formula. Installs
to `$HOMEBREW_PREFIX/bin/codex`.

**AI CLIs** (npm — no brew package yet): `@anthropic-ai/claude-code`

**Dev prerequisites** (formula): `git`, `node`, `python`, `gh`, `jq`,
`ripgrep`, `wget`

The exact lists live near the top of [`bootstrap.sh`](./bootstrap.sh) in the
`FORMULAE`, `CASKS`, and `NPM_PACKAGES` arrays — edit there if you want to
add or remove tools.

---

## Prerequisites

- macOS (Apple Silicon or Intel)
- Admin password (Xcode CLI Tools + Homebrew need it)
- Working HTTPS to `github.com` and `raw.githubusercontent.com`
- ~12 GB free disk space (16 GUI apps + CLIs)

The script itself installs Xcode Command Line Tools and Homebrew if they're
missing — you don't need them up-front.

---

## Running on a fresh Mac

```bash
git clone <this-repo>
cd ai-demo-strap
./bootstrap.sh
```

Or one-shot from a URL:

```bash
curl -fsSL https://raw.githubusercontent.com/dogeared/ai-demo-strap/refs/heads/main/bootstrap.sh -o bootstrap.sh && bash bootstrap.sh
```

What happens, in order:

1. Preflight (macOS check, arch detection, non-root check)
2. Xcode Command Line Tools — pops the GUI installer if missing
3. Homebrew install + `brew update`
4. Brew formulae (CLIs + dev prereqs)
5. Brew casks (all the desktop apps)
6. npm packages (Claude Code, Codex CLI) — global prefix is set to
   `~/.npm-global` so no sudo is needed
7. Summary of what landed on PATH and in `/Applications`
8. **Auth phase** — asks once whether to walk through sign-in for each tool,
   then per-tool y/n. CLIs run interactively; GUI apps launch via `open -a`
   and the script waits for you to confirm before moving on.

After the script finishes, **open a new terminal** so `~/.zprofile` PATH
updates take effect.

---

## Uninstall mode

```bash
./bootstrap.sh --uninstall
```

Removes everything the script installed, in safe order:

1. npm packages (so node can be removed cleanly afterward)
2. Casks
3. Formulae (reverse dependency order; refuses to break installed dependents)
4. `brew autoremove` for orphaned deps
5. **Asks** before wiping per-tool user config / credentials (recommended
   between events)
6. **Asks** before removing brew/npm PATH lines from `~/.zprofile`
7. **Asks** before uninstalling Homebrew itself (off by default)

Xcode Command Line Tools are never touched — too painful to reinstall.

---

## Authentication phase

After install, the script offers to walk you through signing in to:

| Tool | How it's done |
|------|--------------|
| GitHub CLI | `gh auth login --web` — runs inline, browser flow |
| Gemini CLI | runs `gemini` inline; follow OAuth prompt |
| Claude Code | **opens a new terminal window** running `claude` — pick theme, `/login`, then close that window |
| OpenAI Codex CLI | **opens a new terminal window** running `codex` — `/login`, then close that window |
| Cursor | opens app; sign in via Settings → Account |
| Windsurf | opens app; sign in on welcome screen |
| Claude (desktop) | opens app; Anthropic account |
| ChatGPT (desktop) | opens app; OpenAI account |
| Codex (desktop) | opens app; OpenAI account |
| Google Gemini (desktop) | opens app; Google account |

Each is y/n — skip the ones you don't need. For the two "new Terminal window"
tools, the script waits for you to press Enter after you've finished —
analogous to the desktop apps. If something hangs or crashes in that
window, just close it and press Enter in the script to move on.

### Why Claude Code and Codex CLI open in a new window

These two CLIs run full-screen TUIs (theme picker, slash commands, etc.)
that can take over the current terminal. Spawning them in a separate
window means a hang or crash in those tools doesn't block the rest of
the auth phase — you can close that window and continue.

**Which terminal opens?** The script prefers **iTerm2** if installed
(which it is, since iTerm2 is in the cask list) and falls back to
**Terminal.app** otherwise. If you've seen Claude Code hang or Codex
panic inside iTerm2 under UTM, the most reliable workaround is to run
the command manually in Terminal.app — see "Manual auth" below.

### Manual auth (if the scripted flow fails)

You can run any of these at any time after install:

```bash
# CLIs
gh auth login --web
gemini                         # follow OAuth prompt
claude                         # then type /login at the prompt
codex                          # then type /login at the prompt

# Desktop apps — open and sign in with their respective accounts
open -a Cursor
open -a Windsurf
open -a Claude
open -a ChatGPT
open -a Codex
open -a Gemini
```

If `claude` or `codex` hangs/crashes in your current terminal, try the
same command in **Terminal.app** specifically (the stock macOS terminal),
which is the most reliable host for TUIs inside a UTM VM.

---

## Gotchas on fresh installs

### "SSL certificate problem: unable to get local issuer certificate"

Two causes, in order of likelihood:

**1. System clock is wrong** (very common in UTM/QEMU VMs).
Recent TLS certs appear "not yet valid" when the clock is months in the past.

```bash
sudo sntp -sS time.apple.com
date   # confirm it jumped to today
```

Or: System Settings → General → Date & Time → enable "Set time and date
automatically".

**2. TLS-inspecting proxy on the network** (Zscaler, Netskope, Palo Alto,
corporate firewalls).

The host Mac probably has the corp root CA installed, but a fresh VM has
only Apple's defaults — so the intercepted cert isn't trusted.

Diagnose:

```bash
echo | openssl s_client -connect github.com:443 -servername github.com 2>/dev/null \
  | openssl x509 -noout -issuer -subject
```

If the issuer is something like `Zscaler`, `Netskope`, or your company's
name (not a public CA like Sectigo/DigiCert/Let's Encrypt), you're being
intercepted.

Fix: install the corp root CA into the VM's System Keychain.

```bash
# On the host, export it (or get the .pem from IT):
security find-certificate -a -p -c "<corp-CA-name>" \
  /Library/Keychains/System.keychain > corp-ca.pem

# Copy corp-ca.pem into the VM, then in the VM:
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain corp-ca.pem
```

Or sidestep entirely: tether the VM through a phone hotspot or any
non-corporate network for the bootstrap run.

### Quarantine on first launch

macOS Gatekeeper may flag a cask-installed app on first launch
("downloaded from the internet"). If that gets in the way:

```bash
xattr -d com.apple.quarantine "/Applications/<App>.app"
```

### Homebrew not on PATH in the same terminal

The script adds `brew shellenv` to `~/.zprofile`, which takes effect on
new shells. If you want it in the current shell:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"     # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"        # Intel
```

---

## Customizing the tool list

Edit the arrays near the top of `bootstrap.sh`:

```bash
FORMULAE=( git node python gh jq ... )
CASKS=(    cursor windsurf claude chatgpt ... )
NPM_PACKAGES=( "@anthropic-ai/claude-code" "@openai/codex" )
```

If you add a cask, also add it to the `case "$cask" in ... esac` block so
the script can detect dragged-from-DMG installs (and to the summary loop
if you want it in the post-install checklist).

If a tool you're adding needs an auth step, append a `Name|note|command`
entry to `AUTH_TOOLS` further down.
