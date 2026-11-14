#!/usr/bin/env bats
# check-update and list.

load helpers

setup() { setup_ghpkg; }

@test "check-update lists each package and a summary" {
  make_pkgbuild old-gh me/old 1.0
  installed old-gh 1.0-1
  serve_release me/old v1.1
  make_pkgbuild new-gh me/new 2.0
  installed new-gh 2.0-1
  serve_release me/new v2.0
  make_pkgbuild absent-gh me/absent 3.0
  serve_release me/absent v3.0

  run ghpkg check-update
  [[ $status -eq 0 ]]
  [[ ${lines[0]} == "absent-gh 3.0-1 (not installed)" ]]
  [[ ${lines[1]} == "new-gh 2.0-1 (up to date)" ]]
  [[ ${lines[2]} == "old-gh 1.0-1 -> 1.1" ]]
  [[ ${lines[3]} == "ghpkg: 1 packages can be updated. 1/3 packages up-to-date. 1 not installed." ]]
  [[ ${lines[4]} == 'run `ghpkg update`' ]]
}

@test "with nothing to update there's no 'run ghpkg update' line" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.0
  run ghpkg check-update
  [[ $status -eq 0 ]]
  [[ ${lines[-1]} == "ghpkg: 0 packages can be updated. 1/1 packages up-to-date." ]]
}

@test "a built-but-not-installed package counts as updatable" {
  make_pkgbuild app-gh me/app 1.1
  installed app-gh 1.0-1
  serve_release me/app v1.1
  run ghpkg check-update
  [[ ${lines[0]} == "app-gh 1.0-1 -> 1.1-1 (built but not installed yet)" ]]
  [[ ${lines[1]} == "ghpkg: 1 packages can be updated. 0/1 packages up-to-date." ]]
}

@test "a package GitHub can't answer for is reported, and the exit code is 1" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  export GHPKG_TEST_OFFLINE=1
  run ghpkg check-update
  [[ $status -eq 1 ]]
  [[ $output == *"app-gh: couldn't read the latest release of me/app: couldn't reach GitHub"* ]]
  [[ $output == *"0/1 packages up-to-date. 1 couldn't be checked."* ]]
}

@test "check-update with no packages says 0/0" {
  run ghpkg check-update
  [[ $status -eq 0 ]]
  [[ $output == "ghpkg: 0 packages can be updated. 0/0 packages up-to-date." ]]
}

@test "list shows versions and repos without asking GitHub" {
  make_pkgbuild app-gh me/app 1.2
  installed app-gh 1.2-1
  make_pkgbuild other-gh you/other 3.0
  export GHPKG_TEST_OFFLINE=1
  run ghpkg list
  [[ $status -eq 0 ]]
  [[ ${lines[0]} == PACKAGE*INSTALLED*PKGBUILD*GITHUB ]]
  [[ ${lines[1]} =~ ^app-gh\ +1\.2-1\ +1\.2-1\ +me/app$ ]]
  [[ ${lines[2]} =~ ^other-gh\ +-\ +3\.0-1\ +you/other$ ]]
  [[ ! -s $GHPKG_TEST_LOG/curl ]]
}

@test "list with no packages says so" {
  run ghpkg list
  [[ $output == "No packages yet in $GHPKG_ROOT." ]]
}
