# ccv

[한국어](README.ko.md)

**Claude Code Version Manager** — Install, switch, and manage multiple Claude Code versions with a single symlink.

```
ccv install 1.3.0 && ccv use 1.3.0
```

Inspired by `nvm`, built for `zsh`.

## Quick Start

Install it, reload your shell, and start managing Claude Code versions.
You need `zsh` and `git`.

```sh
# install
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | sh

# reload your shell
source ~/.zshrc

# install and activate a version
ccv install 1.3.0
ccv use 1.3.0
ccv current    # → 1.3.0
```

## Install Methods

If you're not sure, use the installer.

### Recommended installer

```sh
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | sh
```

This installs `ccv` to `~/.ccv`, adds the `source` line to `~/.zshrc`, and enables zsh completion automatically.

### Install a specific version

```sh
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | CCV_VERSION=v0.1.0 sh
```

`CCV_VERSION` accepts any git tag or branch name (default: `main`).

### Manual install

```sh
git clone --depth 1 https://github.com/CoodingPenguin/ccv.git ~/.ccv
echo 'fpath=("$HOME/.ccv/completions" $fpath)' >> ~/.zshrc
echo '[[ -f "$HOME/.ccv/ccv.sh" ]] && source "$HOME/.ccv/ccv.sh"' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

## Usage

```
ccv <command> [options]

Commands:
  current                Show active version
  ls                     List installed versions
  ls-remote [N]          List available versions (default 15)
  install <version>      Install a version
  use [version]          Switch version (default: latest installed)
  rm <version>           Remove a version
  upgrade                Install latest + switch to it
  self-update            Update ccv itself
  notify [on|off]        Toggle new-version notifications
  --help, -h             Show help
  --version, -v          Show version
```

### Install a version

```sh
ccv install 1.3.0          # install a specific version
ccv upgrade                # install the latest + switch to it
```

### List versions

```sh
ccv ls                     # installed versions (active one highlighted)
ccv ls-remote              # latest 15 versions from the registry
ccv ls-remote 50           # latest 50 versions
```

### Switch version

```sh
ccv use 1.3.0              # switch to a specific version
ccv use                    # switch to the latest installed
ccv current                # show active version
```

Switching updates the symlink at `CCV_LINK` (default `~/.local/bin/claude`) to point at the selected version.

### Remove a version

```sh
ccv rm 1.2.0
```

### Notifications

```sh
ccv notify on              # enable new-version notifications
ccv notify off             # disable
```

When enabled, `ccv` periodically checks the registry and hints when a newer version is available.

### Update ccv itself

```sh
ccv self-update
```

For git-based installs (default `~/.ccv`), this runs `git pull` and re-sources `ccv.sh`.

## Tab Completion

The installer sets up zsh tab completion automatically:

```
ccv <TAB>         → current, ls, ls-remote, install, use, rm, upgrade, self-update, notify
ccv use <TAB>     → list installed versions
ccv rm <TAB>      → list installed versions
ccv install <TAB> → suggest remote versions
```

For manual installs, make sure your `.zshrc` has:

```zsh
fpath=("$HOME/.ccv/completions" $fpath)
autoload -Uz compinit && compinit
```

## Configuration

| Env var      | Default                          | Description                   |
| ------------ | -------------------------------- | ----------------------------- |
| `CCV_DIR`    | `~/.local/share/claude/versions` | Where versions are installed  |
| `CCV_LINK`   | `~/.local/bin/claude`            | Symlink path for `claude`     |

Make sure the directory containing `CCV_LINK` is on your `PATH`.

## How it works

Each version is installed under `CCV_DIR/<version>/`.
`ccv use <version>` updates a single symlink at `CCV_LINK` so `claude` points at the chosen version.
Switching is instant — no reinstall, no rebuild.

## Requirements

- **zsh**
- **git**

## Uninstall

```sh
~/.ccv/uninstall.sh
```

This removes `~/.ccv` and the `source` lines from `~/.zshrc`.
Installed Claude Code versions under `CCV_DIR` are kept.

## License

[MIT](LICENSE)
