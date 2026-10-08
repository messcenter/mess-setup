#!/bin/sh
# MESS CLI installer.
#
#   sh install.sh --setup
#   bunx --bun --package <GitHub release tarball URL> mess-setup
#
# Env:
#   MESS_VERSION   release tag to install (default: latest)
#   MESS_BIN_DIR   install directory (default: $HOME/.local/bin)
#   MESS_BASE_URL  download base, for mirrors/air-gapped installs
#
# POSIX sh only. Piping into `sh` ignores the shebang, so on Debian/Ubuntu this
# runs under dash: no arrays, no ${var/a/b}, no `set -o pipefail` (dash < 0.5.12).
set -eu

REPO="messcenter/mess-cli"
BIN_DIR="${MESS_BIN_DIR:-$HOME/.local/bin}"

die() { echo "$@" >&2; exit 1; }

tmp=""
staged=""
cleanup() {
	if [ -n "$tmp" ]; then rm -rf "$tmp"; fi
	if [ -n "$staged" ]; then rm -f "$staged"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

setup=0
assume_yes=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--setup) setup=1; shift ;;
		--install-only) setup=0; shift ;;
		--yes) assume_yes=1; shift ;;
		--help|-h)
			printf '%s\n' 'MESS CLI installer' 'Usage: sh install.sh [--setup | --install-only] [--yes] [--directory PATH]' '' '--setup         Install the CLI and open mess dev setup' '--install-only  Install the CLI without opening setup' '--yes           Approve installation of missing gh system packages' '' 'GitHub login still requires your authorization. No Node or Bun is needed for this shell installer.'
			exit 0 ;;
		*) break ;;
	esac
done
if [ "$setup" -eq 0 ] && [ "$#" -gt 0 ]; then die "unexpected arguments: use --setup before dev setup options"; fi
has_terminal() { ( : < /dev/tty ) 2>/dev/null; }
if [ "$setup" -eq 1 ]; then
	[ -t 1 ] && has_terminal || die "Setup requires an interactive terminal. Use --install-only to install without the wizard."
fi

confirm_system_install() {
	if [ "$assume_yes" -eq 1 ]; then return; fi
	has_terminal || die "No interactive terminal. Install gh first, or pass --yes to approve system packages."
	printf 'Install missing GitHub CLI (gh) using the system package manager? [y/N] ' > /dev/tty
	read -r answer < /dev/tty || die "installation cancelled"
	case "$answer" in y|Y|yes|YES) ;; *) die "installation cancelled" ;; esac
}

ensure_github_cli() {
	if command -v gh >/dev/null 2>&1; then return; fi
	case "$os" in
		Linux)
			[ -r /etc/os-release ] || die "Install GitHub CLI (gh) for this Linux distribution first"
			. /etc/os-release
			[ "${ID:-}" = ubuntu ] || die "Automatic gh installation supports Ubuntu; install gh for your distribution first"
			confirm_system_install
			if [ "$(id -u)" -eq 0 ]; then
				apt-get update
				apt-get install -y gh ca-certificates
			else
				command -v sudo >/dev/null 2>&1 || die "sudo is required to install gh"
				sudo apt-get update
				sudo apt-get install -y gh ca-certificates
			fi ;;
		Darwin)
			command -v brew >/dev/null 2>&1 || die "Install Homebrew and rerun, or install GitHub CLI (gh) manually"
			confirm_system_install
			brew install gh ;;
	esac
	command -v gh >/dev/null 2>&1 || die "gh installation did not put gh on PATH"
}

ensure_github_login() {
	if gh auth status --hostname github.com >/dev/null 2>&1; then return; fi
	has_terminal || die "GitHub login required: run gh auth login --hostname github.com in a terminal"
	printf '%s\n' 'Sign in to GitHub. On a remote server, open the displayed URL and enter the device code on your own computer.'
	gh auth login --hostname github.com --git-protocol https --web < /dev/tty || die "GitHub sign-in failed; check your account and any GH_TOKEN/GITHUB_TOKEN override"
	gh auth status --hostname github.com >/dev/null 2>&1 || die "GitHub login is still unavailable"
}



os="$(uname -s)"
arch="$(uname -m)"
case "$os-$arch" in
	Linux-x86_64) asset="mess-linux-x64" ;;
	Darwin-arm64) asset="mess-darwin-arm64" ;;
	*) die "unsupported platform: $os-$arch (supported: Linux x86_64, macOS arm64)" ;;
esac

# Reuse an installed, compatible CLI when no specific release was requested.
# This also prevents an older published release from replacing a newer local CLI.
if [ "$setup" -eq 1 ] && [ -z "${MESS_VERSION:-}" ] && [ -x "$BIN_DIR/mess" ]; then
	installed_help="$("$BIN_DIR/mess" dev setup --help 2>/dev/null || true)"
	case "$installed_help" in
		*--directory*)
			printf '%s\n' "==> using installed CLI: $BIN_DIR/mess"
			PATH="$BIN_DIR:$PATH"
			export PATH
			exec "$BIN_DIR/mess" dev setup "$@" < /dev/tty ;;
	esac
fi

tag="${MESS_VERSION:-latest}"
if [ -n "${MESS_BASE_URL:-}" ]; then
	base="$MESS_BASE_URL"
else
	ensure_github_cli
	ensure_github_login
	if [ "$tag" = "latest" ]; then
		tag="$(gh release view --repo "https://github.com/$REPO" --json tagName --jq .tagName)" || die "Cannot access the CLI release; check your GitHub repository permissions"
	fi
fi
case "$tag" in
	""|*[!a-zA-Z0-9._-]*|-*|*..*) die "invalid release tag" ;;
esac

# sha256sum ships with coreutils (Linux); macOS ships shasum instead. Both read
# the `<hash>  <file>` format the release job writes.
if command -v sha256sum >/dev/null 2>&1; then
	verify() { sha256sum -c "$1"; }
elif command -v shasum >/dev/null 2>&1; then
	verify() { shasum -a 256 -c "$1"; }
else
	die "no sha256 tool found (need sha256sum or shasum)"
fi

tmp="$(mktemp -d)"

echo "==> downloading $asset ($tag)"
if [ -n "${MESS_BASE_URL:-}" ]; then
	command -v curl >/dev/null 2>&1 || die "curl is required for mirror downloads"
	curl -fsSL "$base/$asset" -o "$tmp/$asset"
	curl -fsSL "$base/$asset.sha256" -o "$tmp/$asset.sha256"
else
	gh release download "$tag" --repo "https://github.com/$REPO" \
		--pattern "$asset" --pattern "$asset.sha256" --dir "$tmp" \
		|| die "Cannot download the CLI release; check repository access and release assets"
fi

echo "==> verifying checksum"
( cd "$tmp" && verify "$asset.sha256" ) || die "checksum verification failed — refusing to install"

mkdir -p "$BIN_DIR"

# Stage inside BIN_DIR, then rename(2) into place. The swap is atomic and works
# even while an older `mess` is executing, which a plain overwrite cannot (ETXTBSY).
staged="$BIN_DIR/.mess.$$"
cp "$tmp/$asset" "$staged"
chmod 0755 "$staged"
version="$("$staged" --version)" || die "downloaded binary failed to run; existing installation preserved"
if [ "$setup" -eq 1 ]; then
	setup_help="$("$staged" dev setup --help 2>/dev/null)" || die "This CLI release does not support dev setup; existing installation preserved"
	case "$setup_help" in
		*--directory*) ;;
		*) die "This CLI release predates dev setup. A compatible CLI release must be published; existing installation preserved" ;;
	esac
fi
mv -f "$staged" "$BIN_DIR/mess"
staged=""

echo "==> installed mess $version -> $BIN_DIR/mess"

case ":$PATH:" in
	*":$BIN_DIR:"*) ;;
	*) echo "    warning: $BIN_DIR is not on your PATH" ;;
esac

if [ "$setup" -eq 1 ]; then
	# A pipe-fed shell must not pass its script pipe to gh or the interactive wizard.
	has_terminal || die "CLI installed. Run $BIN_DIR/mess dev setup from an interactive terminal."
	PATH="$BIN_DIR:$PATH"
	export PATH
	cleanup
	tmp=""
	exec "$BIN_DIR/mess" dev setup "$@" < /dev/tty
fi
