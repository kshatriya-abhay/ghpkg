#!/usr/bin/env bats
# Working out each package's state, and reading versions from tags.

load helpers

setup() {
  setup_ghpkg
  load_lib
}

@test "a newer release means 'release'" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1
  plan app-gh
  [[ $STATE == release && $LATEST == 1.1 && $INSTALLED == 1.0-1 ]]
}

@test "the same release, installed, means 'ok'" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.0
  plan app-gh
  [[ $STATE == ok ]]
}

@test "the same release, not installed, means 'missing'" {
  make_pkgbuild app-gh me/app 1.0
  serve_release me/app v1.0
  plan app-gh
  [[ $STATE == missing && -z $INSTALLED ]]
}

@test "a PKGBUILD newer than the installed version means 'install'" {
  make_pkgbuild app-gh me/app 1.1
  installed app-gh 1.0-1
  serve_release me/app v1.1
  plan app-gh
  [[ $STATE == install && $CURRENT == 1.1-1 ]]
}

@test "a tag without a leading v works too" {
  make_pkgbuild app-gh me/app 0.5.3
  installed app-gh 0.5.3-1
  serve_release me/app 0.5.4
  plan app-gh
  [[ $STATE == release && $LATEST == 0.5.4 ]]
}

@test "tags become versions, and unusable tags are refused" {
  [[ $(tag_to_pkgver v2.6.3) == 2.6.3 ]]
  [[ $(tag_to_pkgver 0.5.4) == 0.5.4 ]]
  [[ $(tag_to_pkgver v1.0.0+build.2) == 1.0.0+build.2 ]]
  run tag_to_pkgver 1.0-beta
  [[ $status -ne 0 ]]
  run tag_to_pkgver v
  [[ $status -ne 0 ]]
}

@test "an unusable tag is reported, not used" {
  make_pkgbuild app-gh me/app 1.0
  serve_release me/app v1.1-rc1
  run plan app-gh
  [[ $status -ne 0 ]]
  plan app-gh || true
  [[ $PLAN_ERROR == *"tagged 'v1.1-rc1'"* ]]
}

@test "a PKGBUILD without _ghrepo is reported" {
  make_pkgbuild app-gh me/app 1.0
  sed -i '/^_ghrepo=/d' "$GHPKG_ROOT/app-gh/PKGBUILD"
  plan app-gh || true
  [[ $PLAN_ERROR == *"doesn't set _ghrepo"* ]]
}
