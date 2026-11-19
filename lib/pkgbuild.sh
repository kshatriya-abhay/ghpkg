# shellcheck shell=bash
# Reading the PKGBUILDs in $GHPKG_ROOT. Each package is a folder named after
# its pkgname, holding a PKGBUILD that sets _ghrepo=owner/repo.

# Every package folder's name, one per line, sorted.
all_pkgs() {
  local file
  for file in "$GHPKG_ROOT"/*/PKGBUILD; do
    [[ -f $file ]] || continue
    file=${file%/PKGBUILD}
    echo "${file##*/}"
  done
}

# Package names as pacman allows them. Checked wherever a name from the
# command line becomes a path, so "../x" can't reach outside $GHPKG_ROOT.
valid_pkgname() { [[ $1 =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; }

has_pkg() { valid_pkgname "$1" && [[ -f $GHPKG_ROOT/$1/PKGBUILD ]]; }

# A PKGBUILD variable or array, one item per line, read the way makepkg reads it.
pkgvar() { pkgfile_var "$GHPKG_ROOT/$1/PKGBUILD" "$2"; }

# The same, from a PKGBUILD file at any path.
pkgfile_var() {
  (
    set +eu
    # shellcheck disable=SC1090,SC1091
    source "$1"
    eval "printf '%s\n' \"\${$2[@]}\""
  )
}

# The file name makepkg saves a source as, and the URL it downloads it from.
# A source is either a URL or "name::URL".
source_name() {
  if [[ $1 == *::* ]]; then
    echo "${1%%::*}"
  else
    echo "${1##*/}"
  fi
}

source_url() { echo "${1#*::}"; }
