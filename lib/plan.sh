# shellcheck shell=bash disable=SC2034 # plan sets globals that its callers read
# Working out what a package needs.

# Sets, for one package:
#   REPO       owner/repo from the PKGBUILD
#   PKGVER     the PKGBUILD's pkgver, and CURRENT, its pkgver-pkgrel
#   INSTALLED  the installed version, or empty
#   LATEST     the latest release's version
#   STATE      one of:
#     release  GitHub has a newer version than the PKGBUILD
#     install  the PKGBUILD is newer than what's installed (a build that didn't finish)
#     missing  not installed
#     ok       nothing to do
# Returns 1 with PLAN_ERROR set when the latest release can't be read.
plan() {
  local pkg=$1 tag
  PLAN_ERROR=
  REPO=$(pkgvar "$pkg" _ghrepo)
  PKGVER=$(pkgvar "$pkg" pkgver)
  CURRENT=$PKGVER-$(pkgvar "$pkg" pkgrel)
  INSTALLED=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}') || INSTALLED=

  if [[ -z $REPO ]]; then
    PLAN_ERROR="its PKGBUILD doesn't set _ghrepo"
    return 1
  fi
  if ! fetch_release "$REPO"; then
    PLAN_ERROR="couldn't read the latest release of $REPO: $GH_ERROR"
    return 1
  fi
  tag=$(jq -r '.tag_name // empty' <<<"$RELEASE")
  if ! LATEST=$(tag_to_pkgver "$tag"); then
    PLAN_ERROR="the latest release of $REPO is tagged '$tag', which isn't usable as a version"
    return 1
  fi

  if (( $(vercmp "$LATEST" "$PKGVER") > 0 )); then
    STATE=release
  elif [[ -z $INSTALLED ]]; then
    STATE=missing
  elif (( $(vercmp "$CURRENT" "$INSTALLED") > 0 )); then
    STATE=install
  else
    STATE=ok
  fi
}
