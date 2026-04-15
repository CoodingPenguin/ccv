#!/bin/sh
# ccv uninstaller
set -e

GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
RED=$(printf '\033[0;31m')
NC=$(printf '\033[0m')

info() { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }
err()  { printf " %s✗%s %s\n" "$RED" "$NC" "$*" >&2; }

CCV_DIR="${CCV_DIR:-$HOME/.ccv}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BLOCK_START="# ccv - Claude Code Version Manager"
BLOCK_END="# /ccv - Claude Code Version Manager"

remove_shell_config() {
  [ -f "$ZSHRC" ] || return 0

  temp="${ZSHRC}.tmp.$$"
  awk '
    BEGIN { skip = 0 }
    $0 == block_start { skip = 1; next }
    $0 == block_end   { skip = 0; next }
    skip { next }
    { print }
  ' block_start="$BLOCK_START" block_end="$BLOCK_END" "$ZSHRC" > "$temp"

  mv "$temp" "$ZSHRC"
  ok "Removed ccv config from $ZSHRC"
}

remove_files() {
  if [ -d "$CCV_DIR" ]; then
    rm -rf "$CCV_DIR"
    ok "Removed $CCV_DIR"
  else
    info "$CCV_DIR not found, skipping"
  fi
}

echo ""
info "Uninstalling ccv..."
remove_shell_config
remove_files
echo ""
ok "ccv uninstalled. Restart your shell to apply."
echo ""
