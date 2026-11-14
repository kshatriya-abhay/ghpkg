# shellcheck shell=bash
# Commands that only look: check-update and list.

check_update() {
  local pkg total=0 updatable=0 current=0 missing=0 failed=0 summary

  for pkg in $(all_pkgs); do
    total=$((total + 1))
    if ! plan "$pkg"; then
      warn "$pkg: $PLAN_ERROR"
      failed=$((failed + 1))
      continue
    fi

    case $STATE in
      release) echo "$pkg ${INSTALLED:-$CURRENT} -> $LATEST"; updatable=$((updatable + 1)) ;;
      install) echo "$pkg $INSTALLED -> $CURRENT (built but not installed yet)"; updatable=$((updatable + 1)) ;;
      missing) echo "$pkg $CURRENT (not installed)"; missing=$((missing + 1)) ;;
      ok) echo "$pkg $CURRENT (up to date)"; current=$((current + 1)) ;;
    esac
  done

  summary="ghpkg: $updatable packages can be updated. $current/$total packages up-to-date."
  (( missing == 0 )) || summary+=" $missing not installed."
  (( failed == 0 )) || summary+=" $failed couldn't be checked."
  echo "$summary"
  # shellcheck disable=SC2016 # the backticks are part of the message
  (( updatable == 0 )) || echo 'run `ghpkg update`'

  (( failed == 0 ))
}

# Every package with its installed version, PKGBUILD version and GitHub repo.
# Asks GitHub nothing, so it works offline.
list() {
  local pkg installed rows=()

  for pkg in $(all_pkgs); do
    installed=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}') || installed=
    rows+=("$pkg"$'\t'"${installed:--}"$'\t'"$(pkgvar "$pkg" pkgver)-$(pkgvar "$pkg" pkgrel)"$'\t'"$(pkgvar "$pkg" _ghrepo)")
  done

  if (( ${#rows[@]} == 0 )); then
    echo "No packages yet in $GHPKG_ROOT."
    return
  fi
  { printf 'PACKAGE\tINSTALLED\tPKGBUILD\tGITHUB\n'; printf '%s\n' "${rows[@]}"; } | column -t -s $'\t'
}
