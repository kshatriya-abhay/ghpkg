#!/usr/bin/env bats
# Reading PKGBUILDs.

load helpers

setup() {
  setup_ghpkg
  load_lib
}

@test "all_pkgs lists package folders that hold a PKGBUILD, sorted" {
  make_pkgbuild zeta-gh me/zeta 1.0
  make_pkgbuild alpha-gh me/alpha 1.0
  mkdir -p "$GHPKG_ROOT/not-a-package"
  [[ $(all_pkgs | paste -sd' ') == "alpha-gh zeta-gh" ]]
}

@test "pkgvar expands variables the way makepkg does" {
  make_pkgbuild app-gh me/app 2.0
  [[ $(pkgvar app-gh _ghrepo) == me/app ]]
  [[ $(pkgvar app-gh source) == https://github.com/me/app/releases/download/v2.0/app-gh-2.0.pkg.tar.zst ]]
}

@test "pkgvar reads arrays one item per line" {
  make_pkgbuild app-gh me/app 1.0
  echo "depends=(gtk3 'qt6-base>=6.6')" >>"$GHPKG_ROOT/app-gh/PKGBUILD"
  [[ $(pkgvar app-gh depends | paste -sd,) == 'gtk3,qt6-base>=6.6' ]]
}

@test "source_name and source_url split a 'name::url' source" {
  [[ $(source_name "app-1.0.deb::https://x/y/app_amd64.deb") == app-1.0.deb ]]
  [[ $(source_url "app-1.0.deb::https://x/y/app_amd64.deb") == https://x/y/app_amd64.deb ]]
  [[ $(source_name "https://x/y/app_amd64.deb") == app_amd64.deb ]]
  [[ $(source_url "https://x/y/app_amd64.deb") == https://x/y/app_amd64.deb ]]
}
