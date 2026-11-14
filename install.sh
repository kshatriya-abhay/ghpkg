#!/bin/bash

# Installs ghpkg as a ghpkg package, ghpkg-gh, from its latest GitHub release,
# so `ghpkg update` keeps ghpkg itself updated. Run it from a checkout:
#
#   git clone https://github.com/kshatriya-abhay/ghpkg && cd ghpkg && ./install.sh
#
# It uses this checkout's ghpkg to install the release, then offers the
# Omarchy hook. Nothing from the checkout is installed directly.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ghpkg=$here/bin/ghpkg
root=${GHPKG_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/pkgbuilds}

say() { printf '\e[32m%s\e[0m\n' "$*"; }
die() { echo "install.sh: $*" >&2; exit 1; }

command -v pacman >/dev/null || die "ghpkg is for Arch Linux and Arch-based systems, and pacman isn't installed here."
(( EUID != 0 )) || die "run it as your user, not root. It asks for sudo when installing."
[[ -t 0 ]] || die "it asks questions and runs sudo, so it needs a terminal."

missing=()
for tool in curl jq makepkg fakeroot bsdtar updpkgsums readelf; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if (( ${#missing[@]} )); then
  die "missing: ${missing[*]}. Install them first: sudo pacman -S --needed curl jq base-devel pacman-contrib libarchive binutils"
fi

say "Installing ghpkg from its latest GitHub release, as the ghpkg package ghpkg-gh"
mkdir -p "$root"
if [[ -d $root/ghpkg-gh ]]; then
  echo "$root/ghpkg-gh exists already; using it."
else
  cp -r "$here/packaging/ghpkg-gh" "$root/"
  echo "Copied its PKGBUILD to $root/ghpkg-gh."
fi
"$ghpkg" update ghpkg-gh

installed=/usr/bin/ghpkg
[[ -x $installed ]] || die "the install didn't finish: $installed is missing"
if [[ $(command -v ghpkg) != "$installed" ]]; then
  echo
  echo "Note: 'ghpkg' on your PATH is $(command -v ghpkg), not $installed."
  echo "Remove that one to use the installed ghpkg, which updates itself."
fi

if command -v omarchy >/dev/null || [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy ]]; then
  echo
  say "Omarchy"
  echo "ghpkg can run at the end of every omarchy update."
  read -r -p "List the ghpkg packages that can be updated, after every omarchy update? [Y/n] " answer
  case ${answer,,} in
    '' | y | yes)
      "$installed" hook install
      echo "(To have it install the updates instead, run: ghpkg hook install --update)"
      ;;
    *) echo "Skipped. Add it later with: ghpkg hook install" ;;
  esac
fi

echo
say "Done"
echo "ghpkg is installed, and 'ghpkg update' now updates ghpkg too. Start with: ghpkg help"
