#!/usr/bin/env bats
# The command line itself: help, version, unknown commands, system checks.

load helpers

setup() { setup_ghpkg; }

@test "--version prints the version" {
  run ghpkg --version
  [[ $status -eq 0 && $output =~ ^ghpkg\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "no arguments prints the usage" {
  run ghpkg
  [[ $status -eq 0 && ${lines[0]} == "Usage: ghpkg <command> [arguments]" ]]
}

@test "help <command> prints that command's help" {
  run ghpkg help update
  [[ $status -eq 0 && ${lines[0]} == "Usage: ghpkg update [package...]" ]]
}

@test "an unknown command fails with the usage" {
  run ghpkg frobnicate
  [[ $status -eq 1 && $output == *"unknown command 'frobnicate'"* ]]
}

@test "on a system without pacman it says ghpkg is for Arch-based systems" {
  local bin=$BATS_TEST_TMPDIR/nopacman
  mkdir -p "$bin"
  ln -s "$(command -v readlink)" "$bin/readlink"
  run env PATH="$bin" /bin/bash "$REPO_DIR/bin/ghpkg" list
  [[ $status -eq 1 && $output == *"for Arch Linux and Arch-based systems"* ]]
}

@test "a missing command is named, with its package" {
  local bin=$BATS_TEST_TMPDIR/nojq
  mkdir -p "$bin"
  for tool in readlink pacman curl vercmp; do
    ln -s "$(PATH=$REPO_DIR/test/stubs:$PATH command -v "$tool")" "$bin/$tool"
  done
  run env PATH="$bin" /bin/bash "$REPO_DIR/bin/ghpkg" check-update
  [[ $status -eq 1 && $output == *"missing commands: jq (from jq)"* ]]
}

@test "lib files can be sourced on their own" {
  for lib in "$REPO_DIR"/lib/*.sh; do
    run bash -c "set -euo pipefail; source '$REPO_DIR/lib/common.sh'; source '$lib'"
    [[ $status -eq 0 ]] || { echo "failed: $lib"; false; }
  done
}
