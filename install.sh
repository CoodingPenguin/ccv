#!/bin/sh
# ccv installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | CCV_VERSION=v0.1.0 sh
set -e

REPO_URL="https://github.com/CoodingPenguin/ccv.git"
CCV_DIR="${CCV_DIR:-$HOME/.ccv}"
CCV_VERSION="${CCV_VERSION:-main}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BLOCK_START="# ccv - Claude Code Version Manager"
BLOCK_END="# /ccv - Claude Code Version Manager"
AUTO_YES=0

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

info() { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }
err()  { printf " %s✗%s %s\n" "$RED" "$NC" "$*" >&2; }

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      -y|--yes) AUTO_YES=1 ;;
    esac
  done
}

ensure_prerequisites() {
  command -v zsh >/dev/null 2>&1 || { err "zsh is required"; exit 1; }
  command -v git >/dev/null 2>&1 || { err "git is required"; exit 1; }
}

confirm_installation() {
  [ -t 0 ] || return 0
  [ "$AUTO_YES" -eq 0 ] || return 0

  echo "  This will:"
  printf "    • Install ccv (%s) to %s\n" "$CCV_VERSION" "$CCV_DIR"
  printf "    • Add source line to %s\n" "$ZSHRC"
  echo ""
  printf "  Continue? [Y/n] "
  read -r REPLY </dev/tty || REPLY=y
  case "$REPLY" in
    n*|N*) info "Cancelled."; exit 0 ;;
  esac
  echo ""
}

install_files() {
  if [ -d "$CCV_DIR/.git" ]; then
    info "Updating ccv in ${DIM}${CCV_DIR}${NC}..."
    git -C "$CCV_DIR" fetch --tags --quiet origin
    git -C "$CCV_DIR" checkout --quiet "$CCV_VERSION"
    git -C "$CCV_DIR" pull --ff-only --quiet 2>/dev/null || true
  else
    info "Installing ccv (${CCV_VERSION}) to ${DIM}${CCV_DIR}${NC}..."
    [ -e "$CCV_DIR" ] && { err "$CCV_DIR exists but is not a git repo"; exit 1; }
    git clone --quiet "$REPO_URL" "$CCV_DIR"
    git -C "$CCV_DIR" checkout --quiet "$CCV_VERSION"
  fi
  ok "Files installed."
}

remove_existing_config() {
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
}

configure_shell() {
  touch "$ZSHRC"
  remove_existing_config

  {
    printf '\n%s\n' "$BLOCK_START"
    printf 'fpath=("$HOME/.ccv/completions" $fpath)\n'
    printf '[[ -f "$HOME/.ccv/ccv.sh" ]] && source "$HOME/.ccv/ccv.sh"\n'
    printf '%s\n' "$BLOCK_END"
  } >> "$ZSHRC"

  ok "Updated ${ZSHRC}"
}

print_summary() {
  echo ""
  ok "ccv installed successfully!"
  echo ""
  info "Restart your shell or run:"
  printf "   %ssource %s%s\n" "$BOLD" "$ZSHRC" "$NC"
  echo ""
}

main() {
  parse_args "$@"
  ensure_prerequisites

  echo ""
  printf " %sccv%s %sinstaller%s\n" "$BOLD" "$NC" "$DIM" "$NC"
  echo ""

  confirm_installation
  install_files
  configure_shell
  print_summary
}

main "$@"
