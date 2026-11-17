#!/usr/bin/env bash
# Installs claude-code-statusline.
#
#   curl -fsSL https://raw.githubusercontent.com/alefiengo/claude-code-statusline/main/install.sh | bash
#
# Downloads statusline.sh from the latest GitHub release into the Claude Code config directory and adds
# the statusLine block to settings.json, leaving every other setting untouched. Existing files are
# backed up first.
# Pass --yes (`| bash -s -- --yes`) to replace an existing status line without asking.
# Set STATUSLINE_VERSION (`| STATUSLINE_VERSION=v1.0.0 bash`) to install a specific release.

set -euo pipefail

RELEASES='https://github.com/alefiengo/claude-code-statusline/releases'
VERSION="${STATUSLINE_VERSION:-latest}"
if [ "$VERSION" = latest ]; then
  SCRIPT_URL="$RELEASES/latest/download/statusline.sh"
else
  SCRIPT_URL="$RELEASES/download/$VERSION/statusline.sh"
fi
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT="$CONFIG_DIR/statusline.sh"
SETTINGS="$CONFIG_DIR/settings.json"
STAMP=$(date +%Y%m%d-%H%M%S)
ASSUME_YES=false

for arg in "$@"; do
  case "$arg" in
    -y | --yes) ASSUME_YES=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

info() { printf '  %s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# Reads the answer from the terminal, since stdin is the script itself under `curl | bash`.
confirm() {
  local answer=''
  $ASSUME_YES && return 0
  printf '%s [y/N] ' "$1"
  read -r answer 2>/dev/null </dev/tty || { echo; return 1; }
  [[ "$answer" =~ ^[Yy] ]]
}

echo "Installing claude-code-statusline ($VERSION release) into $CONFIG_DIR"

# Requirements
command -v curl >/dev/null || fail "curl is required."
if ! command -v jq >/dev/null; then
  fail "jq is required. Install it first, for example:
  macOS:          brew install jq
  Debian/Ubuntu:  sudo apt install jq
  Fedora:         sudo dnf install jq"
fi
command -v git >/dev/null || info "git not found: the git segment will stay hidden."

mkdir -p "$CONFIG_DIR"

# The command written to settings.json. ~ keeps it portable across machines that share dotfiles.
if [ "$CONFIG_DIR" = "$HOME/.claude" ]; then
  COMMAND='bash ~/.claude/statusline.sh'
else
  COMMAND="bash $SCRIPT"
fi

# Check settings.json before changing anything, so an invalid file stops the install cleanly.
if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null || fail "$SETTINGS is not valid JSON. Fix it and run the installer again."
  current=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  if [ -n "$current" ] && [ "$current" != "$COMMAND" ]; then
    echo "A status line is already configured: $current"
    confirm "Replace it?" || { echo "Nothing changed."; exit 0; }
  fi
fi

# Script: download to a temporary file and check it before replacing anything.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$SCRIPT_URL" -o "$tmp" || fail "Could not download statusline.sh from the $VERSION release."
head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' || fail "The downloaded file is not the expected script."

if [ -e "$SCRIPT" ] || [ -L "$SCRIPT" ]; then
  if [ ! -L "$SCRIPT" ] && cmp -s "$tmp" "$SCRIPT"; then
    info "statusline.sh is already up to date."
  else
    # Moving it aside also keeps a symlink from redirecting the download into its target.
    mv "$SCRIPT" "$SCRIPT.bak-$STAMP"
    info "Backed up the previous statusline.sh to $SCRIPT.bak-$STAMP"
  fi
fi
if [ ! -e "$SCRIPT" ]; then
  cp "$tmp" "$SCRIPT"
  chmod 755 "$SCRIPT"
  info "Installed $SCRIPT"
fi

# Settings: merge the statusLine block, keeping the rest of the file.
block=$(jq -n --arg cmd "$COMMAND" '{type: "command", command: $cmd, refreshInterval: 60}')
if [ -f "$SETTINGS" ]; then
  if [ "$(jq -c '.statusLine' "$SETTINGS")" = "$(jq -c . <<<"$block")" ]; then
    info "settings.json is already configured."
  else
    cp -p "$SETTINGS" "$SETTINGS.bak-$STAMP"
    info "Backed up settings.json to $SETTINGS.bak-$STAMP"
    jq --argjson block "$block" '.statusLine = $block' "$SETTINGS" >"$tmp"
    # Writing through cat keeps the file's permissions and any symlink pointing to it.
    cat "$tmp" >"$SETTINGS"
    info "Added statusLine to $SETTINGS"
  fi
else
  jq -n --argjson block "$block" '{statusLine: $block}' >"$SETTINGS"
  info "Created $SETTINGS"
fi

echo "Done. Restart Claude Code to see the new status line."
