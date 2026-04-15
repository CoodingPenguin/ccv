# ccv

> Claude Code Version Manager — manage multiple Claude Code versions with symlink switching.

Inspired by `nvm`, built for zsh.

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | sh
```

Install a specific version:

```sh
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | CCV_VERSION=v0.1.0 sh
```

Then restart your shell or `source ~/.zshrc`.

### Requirements

- zsh
- git

## Usage

```sh
ccv current                Show active version
ccv ls                     List installed versions
ccv ls-remote [N]          List available versions (default 15)
ccv install <version>      Install a version
ccv use [version]          Switch version (default: latest installed)
ccv rm <version>           Remove a version
ccv upgrade                Install latest + switch to it
ccv self-update            Update ccv itself
ccv notify [on|off]        Toggle new-version notifications
ccv --help                 Show help
ccv --version              Show ccv version
```

### Example

```sh
ccv install 1.2.0
ccv install 1.3.0
ccv use 1.3.0
ccv current      # → 1.3.0
```

## Configuration

| Env var    | Default                                  | Description               |
| ---------- | ---------------------------------------- | ------------------------- |
| `CCV_DIR`  | `~/.local/share/claude/versions`         | Versions directory        |
| `CCV_LINK` | `~/.local/bin/claude`                    | Symlink path for `claude` |

Make sure `CCV_LINK`'s directory is on your `PATH`.

## Updating

```sh
ccv self-update
```

## Uninstall

```sh
~/.ccv/uninstall.sh
```

## License

MIT
