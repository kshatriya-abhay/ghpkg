# shellcheck shell=bash
# Commands that change things: update and remove.

# makepkg's folders, all under the cache so the packages folder only ever
# holds PKGBUILDs.
use_build_dirs() {
  export BUILDDIR=$GHPKG_CACHE/build SRCDEST=$GHPKG_CACHE/sources PKGDEST=$GHPKG_CACHE/packages
  mkdir -p "$BUILDDIR" "$SRCDEST" "$PKGDEST"
}

# Points the PKGBUILD at LATEST and fills in its checksums: GitHub's when the
# release lists them, otherwise the hash of the download. The new PKGBUILD is
# written next to the old one and moved into place only when it's complete: a
# new pkgver with the old checksums would never build, and the next update
# wouldn't fix it, because the PKGBUILD would already be at LATEST.
bump() {
  local pkg=$1 dir=$GHPKG_ROOT/$1 new src digest sums=() unverified=false
  new=$dir/.PKGBUILD.ghpkg-new

  sed -e "s/^pkgver=.*/pkgver=$LATEST/" -e "s/^pkgrel=.*/pkgrel=1/" "$dir/PKGBUILD" >"$new"

  while IFS= read -r src; do
    digest=$(asset_digest "$(source_url "$src")")
    if [[ -n $digest ]]; then
      sums+=("'$digest'")
    else
      unverified=true
    fi
  done < <(pkgfile_var "$new" source)

  if $unverified; then
    warn "$pkg: GitHub lists no checksum for this release, so it can't be verified. Using the hash of the download."
    if ! (cd "$dir" && updpkgsums "${new##*/}"); then
      rm -f "$new"
      warn "$pkg: couldn't hash the download, so the PKGBUILD is unchanged."
      return 1
    fi
  else
    sed -i "s/^sha256sums=.*/sha256sums=(${sums[*]})/" "$new"
  fi
  mv "$new" "$dir/PKGBUILD"
}

# Builds and installs, then drops the downloads. PKGDEST keeps the new package
# and the one it replaced, for going back with pacman -U.
build_install() {
  local pkg=$1 src

  find "$PKGDEST" -maxdepth 1 -name "$pkg-*.pkg.tar.*" ! -name "$pkg-${INSTALLED:-none}-*" -delete
  (cd "$GHPKG_ROOT/$pkg" && makepkg --syncdeps --install --force --cleanbuild --clean) || return 1

  while IFS= read -r src; do
    rm -f "$SRCDEST/$(source_name "$src")"
  done < <(pkgvar "$pkg" source)
}

update() {
  local pkg targets=() done=() failed=() bumped checked_sudo=false

  if (( $# )); then
    for pkg; do
      has_pkg "$pkg" || die "no PKGBUILD for $pkg in $GHPKG_ROOT"
      targets+=("$pkg")
    done
  else
    for pkg in $(all_pkgs); do
      pacman -Q "$pkg" &>/dev/null && targets+=("$pkg")
    done
  fi

  use_build_dirs

  for pkg in "${targets[@]}"; do
    if ! plan "$pkg"; then
      warn "$pkg: $PLAN_ERROR"
      failed+=("$pkg")
      continue
    fi

    [[ $STATE != ok ]] || { echo "$pkg $CURRENT is up to date"; continue; }

    # Before the first change: the PKGBUILD is about to be edited and the
    # install needs sudo.
    $checked_sudo || { require_sudo_terminal "update${*:+ $*}"; checked_sudo=true; }

    heading "$pkg: ${INSTALLED:-not installed} -> $([[ $STATE == release ]] && echo "$LATEST" || echo "$CURRENT")"
    bumped=false
    if [[ $STATE == release ]]; then
      bump "$pkg" || { failed+=("$pkg"); continue; }
      CURRENT=$LATEST-1
      bumped=true
    fi

    if build_install "$pkg"; then
      done+=("$pkg")
    elif $bumped; then
      warn "$pkg: build or install failed. Its PKGBUILD now says $CURRENT; run 'ghpkg update $pkg' to retry."
      failed+=("$pkg")
    else
      warn "$pkg: build or install failed. Run 'ghpkg update $pkg' to retry."
      failed+=("$pkg")
    fi
  done

  echo
  (( ${#done[@]} == 0 )) || echo "Updated: ${done[*]}"
  # When ghpkg just updated itself, its Omarchy hook may be out of date too.
  local self
  self=$(pacman -Qoq "$GHPKG_SHARE/integrations/omarchy/ghpkg-update.hook" 2>/dev/null) || self=
  if [[ -n $self ]] && printf '%s\n' "${done[@]}" | grep -qxF "$self"; then
    refresh_stale_hook
  fi
  (( ${#failed[@]} == 0 )) || { echo "Failed: ${failed[*]}"; return 1; }
}

# Uninstalls a package, then offers to delete its PKGBUILD folder. Keeps it
# unless told otherwise.
remove() {
  (( $# == 1 )) || die "usage: ghpkg remove <package>"
  local pkg=$1
  has_pkg "$pkg" || die "no PKGBUILD for $pkg in $GHPKG_ROOT"

  if pacman -Q "$pkg" &>/dev/null; then
    require_sudo_terminal "remove $pkg"
    sudo pacman -R "$pkg" || die "pacman didn't remove $pkg"
  else
    echo "$pkg isn't installed."
  fi

  if confirm "Also delete its PKGBUILD folder, $GHPKG_ROOT/$pkg?" n; then
    rm -rf -- "${GHPKG_ROOT:?}/$pkg"
    find "$GHPKG_CACHE/packages" -maxdepth 1 -name "$pkg-*.pkg.tar.*" -delete 2>/dev/null || true
    echo "Deleted $GHPKG_ROOT/$pkg."
  else
    echo "Kept $GHPKG_ROOT/$pkg. Install it again with: ghpkg update $pkg"
  fi
}
