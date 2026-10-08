# MESS setup

This small public installer downloads the private MESS CLI using your GitHub
account, verifies its checksum, installs it to `~/.local/bin/mess`, and opens
`mess dev setup`. It contains no MESS platform code or credentials.

With Bun installed:

```sh
bunx --bun github:messcenter/mess-setup
```

Without Bun or Node, download the shell installer first:

```sh
curl -fL https://raw.githubusercontent.com/messcenter/mess-setup/main/install.sh -o /tmp/mess-setup.sh
sh /tmp/mess-setup.sh --setup
```

Both entry points use the public GitHub repository; no npm account is needed.
A compatible CLI already installed on this machine is reused unless
`MESS_VERSION` pins a release. On a fresh machine, the private release must
include `dev setup`, and the chosen MESS checkout must include `dev:env`.
The installer detects older CLI releases and preserves any existing install.

Current rollout: the public bootstrap is available; the new private CLI and
platform setup changes still need to be released before fresh-server setup can
complete. `--install-only` can install the existing CLI without starting setup.

The shell installer can install missing `gh` on Ubuntu, or on macOS when
Homebrew is already installed. It asks before installing system packages, then
uses GitHub's device login if needed. Your account must have access to
`messcenter/mess-cli` and `messcenter/mess`. GitHub CLI manages credentials.

Options: `--directory /path/to/mess`, `--install-only`, `--yes` (system package
installation only), and `--help`. Existing CLI installs are replaced only after
checksum verification and a successful binary version check. `MESS_VERSION`
pins a CLI release; `MESS_BIN_DIR` changes the install directory.

Supported binaries: Linux x64 and macOS arm64. Other platforms fail before
system changes. Normal use is then `mess dev setup` and `mess self-update`.
A new terminal must have `~/.local/bin` on PATH.

The bootstrap package has no dependencies and no install lifecycle scripts.
Versioned release tarballs can also be used directly after a bootstrap release:

```sh
bunx --bun --package https://github.com/messcenter/mess-setup/releases/download/v0.1.0/mess-setup.tgz mess-setup
```
