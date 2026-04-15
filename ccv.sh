#!/usr/bin/env zsh
# shellcheck disable=SC1009,SC1036,SC1058,SC1072,SC1073
# ─────────────────────────────────────────────────────────────────────────────
# ccv - Claude Code Version Manager
# Manage multiple Claude Code versions with symlink switching.
#
# Install:
#   source "$HOME/.ccv/ccv.sh"
#
# Usage:
#   ccv current                Show active version
#   ccv ls                     List installed versions
#   ccv ls-remote [N]          List available versions (default 15)
#   ccv install <version>      Install a version
#   ccv use [version]          Switch version (default: latest installed)
#   ccv rm <version>           Remove a version
#   ccv upgrade                Install latest + switch to it
#   ccv self-update            Update ccv itself
#   ccv notify [on|off]        Toggle new version notification
#   ccv --help                 Show help
#   ccv --version              Show ccv version
# ─────────────────────────────────────────────────────────────────────────────

CCV_VERSION="0.1.0"

export CCV_DIR="${CCV_DIR:-$HOME/.local/share/claude/versions}"
export CCV_LINK="${CCV_LINK:-$HOME/.local/bin/claude}"

# disable fzf-tab sorting for ccv (preserve semver order)
zstyle ':completion:*:ccv:*' sort false
zstyle ':fzf-tab:complete:ccv:*' fzf-flags --no-sort

# ── ANSI color utilities ────────────────────────────────────────────────────

if [[ -z "$NO_COLOR" ]] && [[ -t 2 ]]; then
  _ccv_red()     { printf '\033[0;31m%s\033[0m' "$*"; }
  _ccv_green()   { printf '\033[0;32m%s\033[0m' "$*"; }
  _ccv_yellow()  { printf '\033[0;33m%s\033[0m' "$*"; }
  _ccv_cyan()    { printf '\033[0;36m%s\033[0m' "$*"; }
  _ccv_dim()     { printf '\033[2m%s\033[0m' "$*"; }
  _ccv_bold()    { printf '\033[1m%s\033[0m' "$*"; }
else
  _ccv_red()     { printf '%s' "$*"; }
  _ccv_green()   { printf '%s' "$*"; }
  _ccv_yellow()  { printf '%s' "$*"; }
  _ccv_cyan()    { printf '%s' "$*"; }
  _ccv_dim()     { printf '%s' "$*"; }
  _ccv_bold()    { printf '%s' "$*"; }
fi

# ── Logging helpers ─────────────────────────────────────────────────────────

_ccv_log_success() { echo " $(_ccv_green '✓') $*" >&2; }
_ccv_log_error()   { echo " $(_ccv_red '✗') $*" >&2; }
_ccv_log_info()    { echo " $(_ccv_cyan '→') $*" >&2; }

# ── Internal helpers ────────────────────────────────────────────────────────

_ccv_current_version() {
  local target
  target=$(readlink "$CCV_LINK" 2>/dev/null) || return 1
  basename "$target"
}

_ccv_installed_versions() {
  local -a versions
  versions=("$CCV_DIR"/*(N:t))
  if (( ${#versions} > 0 )); then
    printf '%s\n' "${versions[@]}" | sort -V -r
  fi
}

_ccv_version_exists() {
  [[ -f "$CCV_DIR/$1" ]]
}

# ── Subcommands ─────────────────────────────────────────────────────────────

_ccv_cmd_current() {
  local ver
  ver=$(_ccv_current_version) || {
    _ccv_log_error "No active version (symlink not found: $CCV_LINK)"
    return 1
  }
  echo "$ver"
}

_ccv_cmd_ls() {
  local current ver
  current=$(_ccv_current_version 2>/dev/null)
  local -a versions
  versions=( ${(f)"$(_ccv_installed_versions)"} )

  if (( ${#versions} == 0 )); then
    _ccv_log_info "No versions installed in $CCV_DIR"
    return 0
  fi

  for ver in "${versions[@]}"; do
    if [[ "$ver" == "$current" ]]; then
      echo " $(_ccv_green '->') $(_ccv_bold "$ver") $(_ccv_green '*')"
    else
      echo "    $ver"
    fi
  done
}

_ccv_cmd_ls_remote() {
  local count="${1:-15}"
  command -v npm >/dev/null 2>&1 || {
    _ccv_log_error "npm is required"
    return 1
  }

  _ccv_log_info "Fetching versions from npm registry..."
  local -a all_versions
  all_versions=( ${(f)"$(npm view @anthropic-ai/claude-code versions --json 2>/dev/null | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).join('\n'))")"} )

  if (( ${#all_versions} == 0 )); then
    _ccv_log_error "Failed to fetch versions"
    return 1
  fi

  # cache all versions for tab completion (newest first)
  printf '%s\n' "${(Oa)all_versions[@]}" > "$CCV_DIR/.remote-cache"

  # take latest N versions (array is already oldest→newest, reverse it)
  local -a releases
  releases=( ${(Oa)all_versions} )
  (( ${#releases} > count )) && releases=( "${releases[@]:0:$count}" )

  local current ver
  current=$(_ccv_current_version 2>/dev/null)

  for ver in "${releases[@]}"; do
    if [[ "$ver" == "$current" ]]; then
      echo " $(_ccv_green '->') $(_ccv_bold "$ver") $(_ccv_green '✓')"
    elif _ccv_version_exists "$ver"; then
      echo "    $ver $(_ccv_green '✓')"
    else
      echo "    $ver"
    fi
  done
}

_ccv_cmd_install() {
  local version="$1"
  [[ -n "$version" ]] || {
    _ccv_log_error "Usage: ccv install <version>"
    return 1
  }

  if _ccv_version_exists "$version"; then
    _ccv_log_info "Version $version is already installed"
    return 0
  fi

  # remember current version to restore after install
  local prev
  prev=$(_ccv_current_version 2>/dev/null)

  _ccv_log_info "Installing Claude Code $version..."
  curl -fsSL https://claude.ai/install.sh | bash -s -- "$version"
  local rc=$?

  if (( rc != 0 )); then
    _ccv_log_error "Installation failed (exit $rc)"
    return 1
  fi

  # the installer switches the symlink; restore previous version if there was one
  if [[ -n "$prev" ]] && [[ "$prev" != "$version" ]] && _ccv_version_exists "$prev"; then
    ln -sf "$CCV_DIR/$prev" "$CCV_LINK"
    _ccv_log_info "Restored active version to $prev"
  fi

  _ccv_log_success "Installed $version"
}

_ccv_cmd_use() {
  local version="$1"
  if [[ -z "$version" ]]; then
    # no arg: switch to latest installed version
    version=$(_ccv_installed_versions | head -1)
    [[ -n "$version" ]] || {
      _ccv_log_error "No versions installed"
      return 1
    }
  fi

  if ! _ccv_version_exists "$version"; then
    _ccv_log_error "Version $version not installed. Run: ccv install $version"
    return 1
  fi

  ln -sf "$CCV_DIR/$version" "$CCV_LINK"
  _ccv_log_success "Now using Claude Code $(_ccv_bold "$version")"
}

_ccv_cmd_rm() {
  local version="$1"
  [[ -n "$version" ]] || {
    _ccv_log_error "Usage: ccv rm <version>"
    return 1
  }

  if ! _ccv_version_exists "$version"; then
    _ccv_log_error "Version $version not installed"
    return 1
  fi

  local current
  current=$(_ccv_current_version 2>/dev/null)
  if [[ "$version" == "$current" ]]; then
    _ccv_log_error "Cannot remove active version. Switch first: ccv use <other>"
    return 1
  fi

  rm -f "$CCV_DIR/$version"
  _ccv_log_success "Removed $version"
}

_ccv_cmd_upgrade() {
  _ccv_log_info "Checking latest version..."
  local latest
  latest=$(npm view @anthropic-ai/claude-code version 2>/dev/null) || {
    _ccv_log_error "Failed to fetch latest version"
    return 1
  }

  local current
  current=$(_ccv_current_version 2>/dev/null)
  if [[ "$latest" == "$current" ]]; then
    _ccv_log_success "Already on latest: $(_ccv_bold "$current")"
    return 0
  fi

  _ccv_cmd_install "$latest" || return 1
  _ccv_cmd_use "$latest"
}

_ccv_cmd_self_update() {
  local ccv_home="$HOME/.ccv"
  if [[ -d "$ccv_home/.git" ]]; then
    _ccv_log_info "Updating ccv..."
    git -C "$ccv_home" pull --ff-only 2>/dev/null && \
      _ccv_log_success "ccv updated. Run: source ~/.zshrc" || \
      _ccv_log_error "Update failed. Try: cd ~/.ccv && git pull"
  else
    _ccv_log_error "Not a git repo. Reinstall from GitHub to enable self-update"
  fi
}

_ccv_cmd_help() {
  cat <<'EOF'
ccv - Claude Code Version Manager

Usage:
  ccv current                Show active version
  ccv ls                     List installed versions
  ccv ls-remote [N]          List available versions (default 15)
  ccv install <version>      Install a version
  ccv use [version]          Switch version (default: latest installed)
  ccv rm <version>           Remove a version
  ccv upgrade                Install latest + switch to it
  ccv self-update            Update ccv itself
  ccv notify [on|off]        Toggle new version notification
  ccv --help                 Show this help
  ccv --version              Show ccv version

Environment:
  CCV_DIR     Versions directory  (default: ~/.local/share/claude/versions)
  CCV_LINK    Symlink path        (default: ~/.local/bin/claude)
EOF
}

# ── Main dispatcher ─────────────────────────────────────────────────────────

_ccv_check_update() {
  [[ -f "$CCV_DIR/.no-notify" ]] && return
  local cache="$CCV_DIR/.remote-cache"
  [[ -f "$cache" ]] || return
  local latest current
  latest=$(head -1 "$cache")
  current=$(_ccv_current_version 2>/dev/null) || return
  # skip if already on latest, or latest is installed (intentional choice)
  [[ "$latest" == "$current" ]] && return
  _ccv_version_exists "$latest" && return
  echo " 🆕 Claude Code $(_ccv_bold "$latest") available $(_ccv_dim "(current: $current, run: ccv install $latest)")" >&2
}

_ccv_cmd_notify() {
  case "${1:-}" in
    on)  rm -f "$CCV_DIR/.no-notify"; _ccv_log_success "Notifications enabled" ;;
    off) touch "$CCV_DIR/.no-notify"; _ccv_log_success "Notifications disabled" ;;
    *)
      if [[ -f "$CCV_DIR/.no-notify" ]]; then
        echo "notify: $(_ccv_dim 'off') — new version notifications disabled"
      else
        echo "notify: $(_ccv_green 'on') — notifies when a newer version is available"
      fi
      ;;
  esac
}

ccv() {
  case "${1:-}" in
    current)    _ccv_cmd_current ;;
    ls)         _ccv_cmd_ls ;;
    ls-remote)  shift; _ccv_cmd_ls_remote "$@" ;;
    install)    shift; _ccv_cmd_install "$@" ;;
    use)        shift; _ccv_cmd_use "$@" ;;
    rm)         shift; _ccv_cmd_rm "$@" ;;
    upgrade)      _ccv_cmd_upgrade ;;
    self-update)  _ccv_cmd_self_update ;;
    notify)       shift; _ccv_cmd_notify "$@" ;;
    help|--help|-h)  _ccv_cmd_help; return ;;
    --version|-v) echo "ccv $CCV_VERSION"; return ;;
    *)
      if [[ -n "${1:-}" ]]; then
        _ccv_log_error "Unknown command: $1"
      fi
      _ccv_cmd_help
      return 1
      ;;
  esac
  # show update hint after command completes
  _ccv_check_update
}
