# shellcheck shell=bash
# test-build: build a package without installing it, and compare the result
# with the release file it came from.

# The files in a package or .deb, one "mode<TAB>path" line each, without
# metadata or folders. Folders are dropped by their type in the listing, not
# by a trailing slash: some .deb tools store "usr/bin" rather than "usr/bin/".
package_listing() {
  case $1 in
    *.pkg.tar.*) bsdtar -tvf "$1" ;;
    *.deb) bsdtar -xOf "$1" 'data.tar*' | bsdtar -tvf - ;;
  esac | grep -v '^d' |
    sed -E 's/^([^ ]+) +([^ ]+ +){7}/\1\t/; s/ (->|link to) .*$//; s#\t\./#\t#' |
    awk -F '\t' '$2 != "" && $2 != "." && $2 !~ /^\.(PKGINFO|BUILDINFO|MTREE|INSTALL)$/' |
    LC_ALL=C sort -t $'\t' -k2
}

# Just the paths.
package_files() { package_listing "$1" | cut -f2 | sort; }

# Files in both whose permissions differ, as "path<TAB>before<TAB>after".
changed_modes() {
  LC_ALL=C join -t $'\t' -1 2 -2 2 <(package_listing "$1") <(package_listing "$2") |
    awk -F '\t' '$2 != $3'
}

test_build() {
  (( $# == 1 )) || die "usage: ghpkg test-build <package>"
  local pkg=$1 dir log status=0 built original src missing
  has_pkg "$pkg" || die "no PKGBUILD for $pkg in $GHPKG_ROOT"

  dir=$GHPKG_CACHE/test-build/$pkg
  rm -rf "$dir"
  mkdir -p "$dir/build" "$dir/packages" "$GHPKG_CACHE/sources"
  log=$dir/makepkg.log

  echo "Building $pkg in $dir (not installing it)..."
  (
    cd "$GHPKG_ROOT/$pkg"
    BUILDDIR=$dir/build PKGDEST=$dir/packages SRCDEST=$GHPKG_CACHE/sources \
      makepkg --nodeps --force --cleanbuild --clean --noconfirm
  ) >"$log" 2>&1 || status=$?

  grep -E '\.\.\. (Passed|FAILED|Skipped)' "$log" | sed 's/^ */  checksum: /' || true
  if (( status != 0 )); then
    echo "The build failed. The end of makepkg's log ($log):"
    tail -n 20 "$log" | sed 's/^/  /'
    return 1
  fi

  built=$(find "$dir/packages" -name "$pkg-*.pkg.tar.*" ! -name '*-debug-*' | head -1)
  [[ -n $built ]] || die "makepkg finished but left no package in $dir/packages"

  echo
  echo "Built $built"
  bsdtar -xOf "$built" .PKGINFO | jq -R -s -r '
    split("\n") | map(capture("^(?<k>[a-z]+) = (?<v>.*)$")?) | reduce .[] as $e ({}; .[$e.k] += [$e.v])
    | "  \(.pkgname[0]) \(.pkgver[0])",
      "  depends:   \(.depend // [] | join(" "))",
      "  provides:  \(.provides // [] | join(" "))",
      "  conflicts: \(.conflict // [] | join(" "))",
      (if .optdepend then "  optional:  \(.optdepend | map(split(":")[0]) | join(" "))" else empty end)'

  # pacman -T prints the dependencies that nothing installed satisfies.
  mapfile -t missing < <(pkgvar "$pkg" depends | xargs -r pacman -T 2>/dev/null || true)
  if (( ${#missing[@]} )); then
    echo "  Not installed yet, so installing would pull in: ${missing[*]}"
  else
    echo "  Every dependency is already installed."
  fi

  src=$(pkgvar "$pkg" source | head -1)
  original=$GHPKG_CACHE/sources/$(source_name "$src")
  echo
  if [[ ! -f $original ]]; then
    echo "Can't compare with the release file: $original isn't in the cache."
  elif [[ $original != *.pkg.tar.* && $original != *.deb ]]; then
    echo "Can't compare with ${original##*/}: only .pkg.tar.* and .deb sources can be compared."
  else
    local diffs
    diffs=$(diff <(package_files "$original") <(package_files "$built") | grep -E '^[<>]' || true)
    if [[ -z $diffs ]]; then
      echo "Files: the same $(package_files "$built" | wc -l) files as ${original##*/}."
    else
      echo "Files that differ from ${original##*/}:"
      grep '^<' <<<"$diffs" | sed 's#^< #  only in the release file: /#' | head -40 || true
      grep '^>' <<<"$diffs" | sed 's#^> #  only in the build:        /#' | head -40 || true
    fi
    local modes
    modes=$(changed_modes "$original" "$built")
    if [[ -n $modes ]]; then
      echo "Permissions that differ:"
      awk -F '\t' '{ printf "  /%s: %s in the release file, %s in the build\n", $1, $2, $3 }' <<<"$modes" | head -40
    fi
  fi
}
