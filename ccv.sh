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
#   ccv review                 Review changes since current version
#   ccv install <version>      Install a version
#   ccv use [version]          Switch version (default: latest installed)
#   ccv rm <version>           Remove a version
#   ccv upgrade                Install latest + switch to it
#   ccv self-update            Update ccv itself
#   ccv notify [on|off]        Toggle new version notification
#   ccv --help                 Show help
#   ccv --version              Show ccv version
# ─────────────────────────────────────────────────────────────────────────────

CCV_VERSION="0.2.0"

export CCV_DIR="${CCV_DIR:-$HOME/.local/share/claude/versions}"
export CCV_LINK="${CCV_LINK:-$HOME/.local/bin/claude}"
export CCV_CHANGELOG_URL="${CCV_CHANGELOG_URL:-https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md}"

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

_ccv_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    _ccv_log_error "$1 is required"
    return 1
  }
}

_ccv_version_cmp() {
  local left="$1" right="$2"
  [[ "$left" == "$right" ]] && return 0
  local highest
  highest=$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -1)
  [[ "$highest" == "$left" ]] && return 1
  return 2
}

_ccv_fetch_latest_version() {
  _ccv_require_cmd npm || return 1
  npm view @anthropic-ai/claude-code version 2>/dev/null
}

_ccv_fetch_changelog() {
  _ccv_require_cmd curl || return 1
  curl -fsSL "$CCV_CHANGELOG_URL"
}

_ccv_changelog_latest_version() {
  awk '/^## [0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }'
}

_ccv_categorize_line() {
  local line="$1"
  local normalized="${(L)line}"
  case "$normalized" in
    (*fixed*|*crash*|*hang*|*leak*|*corruption*|*regression*|*retry*|*timeout*|*auth*)
      echo "stability"
      ;;
    (*added*|*introduced*|*now available*|*support*)
      echo "new"
      ;;
    (*windows:*|*desktop*|*bedrock*|*vertex*|*foundry*|*remote control*)
      echo "low"
      ;;
    (*)
      echo "other"
      ;;
  esac
}

_ccv_is_risk_line() {
  local line="$1"
  local normalized="${(L)line}"
  case "$normalized" in
    (*agent*|*worktree*|*mcp*|*hook*|*permission*|*config*|*keybinding*|*ctrl+*|*shell*|*bash*|*ide*|*plugin*|*sandbox*)
      return 0
      ;;
    (*)
      return 1
      ;;
  esac
}

_ccv_extract_review_entries() {
  local changelog="$1"
  local current="$2"
  local target="$3"

  awk -v current="$current" -v target="$target" '
    function cmp(a, b,    aa, bb, i, n, av, bv) {
      n = split(a, aa, ".")
      split(b, bb, ".")
      for (i = 1; i <= 3; i++) {
        av = (i <= n ? aa[i] + 0 : 0)
        bv = (i <= 3 ? bb[i] + 0 : 0)
        if (av < bv) return -1
        if (av > bv) return 1
      }
      return 0
    }
    /^## [0-9]+\.[0-9]+\.[0-9]+$/ {
      version = $2
      include = (cmp(version, target) <= 0 && cmp(version, current) > 0)
      next
    }
    /^- / && include {
      print version "\t" substr($0, 3)
    }
  ' <<< "$changelog"
}

_ccv_emit_review_report() {
  local current="$1"
  local latest="$2"
  local target="$3"
  local changelog_latest="$4"
  local version_lines="$5"
  local entries="$6"

  echo "$(_ccv_bold 'Current:') $current"
  echo "$(_ccv_bold 'Latest:') $latest"
  echo "$(_ccv_bold 'Changelog latest:') $changelog_latest"

  if [[ -n "$version_lines" ]]; then
    echo "$(_ccv_bold 'Versions covered:') ${version_lines//$'\n'/, }"
  else
    echo "$(_ccv_bold 'Versions covered:') none"
  fi
  echo

  local -a important_lines risk_lines low_lines
  local stability_count=0
  local new_count=0
  local other_count=0
  local low_count=0
  local total_count=0
  local version text category

  while IFS=$'\t' read -r version text; do
    [[ -n "$version" && -n "$text" ]] || continue
    (( total_count++ ))
    category=$(_ccv_categorize_line "$text")
    case "$category" in
      stability) (( stability_count++ )) ;;
      new)       (( new_count++ )) ;;
      low)       (( low_count++ )) ;;
      *)         (( other_count++ )) ;;
    esac

    if _ccv_is_risk_line "$text"; then
      if (( ${#risk_lines} < 5 )); then
        risk_lines+=("[$version] $text")
      fi
    elif [[ "$category" != "low" ]]; then
      if (( ${#important_lines} < 6 )); then
        important_lines+=("[$version] $text")
      fi
    elif (( ${#low_lines} < 3 )); then
      low_lines+=("[$version] $text")
    fi
  done <<< "$entries"

  echo "$(_ccv_bold 'Important changes:')"
  if (( ${#important_lines} == 0 )); then
    echo "  - No high-signal changes found in documented releases."
  else
    printf '  - %s\n' "${important_lines[@]}"
  fi
  echo

  echo "$(_ccv_bold 'Potential risk areas:')"
  if (( ${#risk_lines} == 0 )); then
    echo "  - No sensitive workflow areas were flagged by the review rules."
  else
    printf '  - %s\n' "${risk_lines[@]}"
  fi
  echo

  echo "$(_ccv_bold 'Recommendation cues:')"
  if [[ "$latest" != "$changelog_latest" ]]; then
    echo "  - npm registry is ahead of the documented changelog. Review is limited to $target and the undocumented release should be treated conservatively."
  fi
  if (( stability_count >= 3 )); then
    echo "  - Stability fixes are prominent since $current; upgrade is worth considering if you hit recent regressions."
  fi
  if (( ${#risk_lines} > 0 )); then
    echo "  - Sensitive areas changed (permissions, agents, MCP, shell, config, or keybindings). Review before upgrading."
  fi
  if (( new_count > stability_count && ${#risk_lines} == 0 )); then
    echo "  - This release window leans toward new capabilities over risky workflow changes."
  fi
  if (( total_count == 0 )); then
    echo "  - No documented changes were found after your current version."
  fi
  if (( ${#low_lines} > 0 )); then
    echo "  - Lower-relevance changes were omitted from the main list to reduce noise."
  fi
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
  _ccv_require_cmd npm || return 1

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

_ccv_cmd_review() {
  local current latest changelog changelog_latest target entries version_lines

  current=$(_ccv_current_version) || {
    _ccv_log_error "No active version (symlink not found: $CCV_LINK)"
    return 1
  }

  latest=$(_ccv_fetch_latest_version) || {
    _ccv_log_error "Failed to fetch latest version"
    return 1
  }

  changelog=$(_ccv_fetch_changelog) || {
    _ccv_log_error "Failed to fetch changelog from $CCV_CHANGELOG_URL"
    return 1
  }

  changelog_latest=$(_ccv_changelog_latest_version <<< "$changelog")
  [[ -n "$changelog_latest" ]] || {
    _ccv_log_error "Failed to parse latest documented version from changelog"
    return 1
  }

  target="$latest"
  if [[ "$latest" != "$changelog_latest" ]]; then
    _ccv_log_info "npm latest is $latest, but documented changelog stops at $changelog_latest"
    target="$changelog_latest"
  fi

  _ccv_version_cmp "$target" "$current"
  case $? in
    0)
      echo "$(_ccv_bold 'Current:') $current"
      echo "$(_ccv_bold 'Latest:') $latest"
      echo "$(_ccv_bold 'Changelog latest:') $changelog_latest"
      echo "$(_ccv_bold 'Versions covered:') none"
      echo
      echo "$(_ccv_bold 'Important changes:')"
      echo "  - Already at the newest documented version."
      echo
      echo "$(_ccv_bold 'Potential risk areas:')"
      echo "  - None flagged."
      echo
      echo "$(_ccv_bold 'Recommendation cues:')"
      if [[ "$latest" != "$changelog_latest" ]]; then
        echo "  - npm registry is ahead of the documented changelog. Hold or inspect the undocumented release manually."
      else
        echo "  - No newer documented release to review."
      fi
      return 0
      ;;
    2)
      _ccv_log_error "Current version $current is newer than the review target $target"
      return 1
      ;;
  esac

  entries=$(_ccv_extract_review_entries "$changelog" "$current" "$target")
  version_lines=$(printf '%s\n' "$entries" | awk -F'\t' 'NF { seen[$1]=1 } END { for (v in seen) print v }' | sort -V -r)
  _ccv_emit_review_report "$current" "$latest" "$target" "$changelog_latest" "$version_lines" "$entries"
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

  # the installer writes the new binary directly to $CCV_LINK as a regular file.
  # move it into the versioned dir before restoring any previous symlink, otherwise
  # `ln -sf` over the regular file would delete the freshly installed binary.
  mkdir -p "$CCV_DIR"
  if [[ -f "$CCV_LINK" && ! -L "$CCV_LINK" ]]; then
    mv -f "$CCV_LINK" "$CCV_DIR/$version"
    chmod +x "$CCV_DIR/$version"
  elif [[ -L "$CCV_LINK" ]] && ! _ccv_version_exists "$version"; then
    # installer kept symlink form but pointed it elsewhere — copy through the link
    local resolved
    resolved=$(readlink "$CCV_LINK")
    if [[ -f "$resolved" ]]; then
      cp "$resolved" "$CCV_DIR/$version"
      chmod +x "$CCV_DIR/$version"
    fi
  fi

  if ! _ccv_version_exists "$version"; then
    _ccv_log_error "Installer finished but $version was not found at $CCV_LINK"
    return 1
  fi

  # restore previous active version; otherwise point the symlink at the new install
  if [[ -n "$prev" ]] && [[ "$prev" != "$version" ]] && _ccv_version_exists "$prev"; then
    ln -sf "$CCV_DIR/$prev" "$CCV_LINK"
    _ccv_log_info "Restored active version to $prev"
  else
    ln -sf "$CCV_DIR/$version" "$CCV_LINK"
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
  local ccv_home="${CCV_HOME:-$HOME/.ccv}"
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
  ccv review                 Review changes since current version
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
  CCV_CHANGELOG_URL
              Changelog source    (default: official GitHub raw changelog)
EOF
}

# ── Main dispatcher ─────────────────────────────────────────────────────────

_ccv_check_update() {
  [[ -f "$CCV_DIR/.no-notify" ]] && return 0
  local cache="$CCV_DIR/.remote-cache"
  [[ -f "$cache" ]] || return 0
  local latest current
  latest=$(head -1 "$cache")
  current=$(_ccv_current_version 2>/dev/null) || return 0
  # skip if already on latest, or latest is installed (intentional choice)
  [[ "$latest" == "$current" ]] && return 0
  _ccv_version_exists "$latest" && return 0
  echo " 🆕 Claude Code $(_ccv_bold "$latest") available $(_ccv_dim "(current: $current, run: ccv review && ccv install $latest)")" >&2
  return 0
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
    review)     _ccv_cmd_review ;;
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
