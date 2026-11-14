# shellcheck shell=bash disable=SC2034 # GHPKG_VERSION is read by bin/ghpkg
# Settings and helpers every command uses. Safe to source on its own.

GHPKG_VERSION=1.0.2

# Where the PKGBUILDs live, and where downloads and builds go. Both can be
# moved with environment variables.
GHPKG_ROOT=${GHPKG_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/pkgbuilds}
GHPKG_CACHE=${GHPKG_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ghpkg}

warn() { echo "ghpkg: $*" >&2; }

# A suggestion, on stderr so it never mixes with output scripts read.
# GHPKG_NO_TIPS=1 turns them off.
tip() { [[ -n ${GHPKG_NO_TIPS:-} ]] || echo "ghpkg tip: $*" >&2; }
die() { warn "$*"; exit 1; }

# A green heading, as `omarchy update` prints them. Plain when not on a terminal.
heading() {
  if [[ -t 1 ]]; then
    printf '\e[32m\n%s\e[0m\n' "$*"
  else
    printf '\n%s\n' "$*"
  fi
}

# The package a command comes from, for "install it with pacman" messages.
tool_package() {
  case $1 in
    makepkg | vercmp) echo pacman ;;
    updpkgsums) echo pacman-contrib ;;
    bsdtar) echo libarchive ;;
    readelf) echo binutils ;;
    *) echo "$1" ;;
  esac
}

# Stops unless this is an Arch-based system with the given commands installed.
require_system() {
  command -v pacman >/dev/null ||
    die "ghpkg is for Arch Linux and Arch-based systems, and pacman isn't installed here."

  local tool missing=()
  for tool; do
    command -v "$tool" >/dev/null || missing+=("$tool (from $(tool_package "$tool"))")
  done
  (( ${#missing[@]} == 0 )) || die "missing commands: ${missing[*]}. Install them with pacman."
}

# Creates the packages folder on first use, and says so.
ensure_root() {
  [[ -d $GHPKG_ROOT ]] && return
  mkdir -p "$GHPKG_ROOT"
  warn "created $GHPKG_ROOT for your PKGBUILDs"
}

# Installing runs sudo, which needs a terminal to ask for the password. Stop
# before any download or build when there is none, instead of failing at the end.
require_sudo_terminal() {
  if ! sudo -n true 2>/dev/null && [[ ! -t 0 ]]; then
    die "sudo needs a password and there's no terminal to ask in. Run 'ghpkg $1' in a terminal."
  fi
}

# Asks a yes/no question. $2 is the answer used on Enter, and without a terminal.
confirm() {
  local question=$1 default=${2:-n} hint answer
  [[ $default == y ]] && hint='[Y/n]' || hint='[y/N]'

  if [[ ! -t 0 ]]; then
    [[ $default == y ]]
    return
  fi

  while true; do
    read -r -p "$question $hint " answer
    case ${answer,,} in
      '') [[ $default == y ]]; return ;;
      y | yes) return 0 ;;
      n | no) return 1 ;;
    esac
  done
}
