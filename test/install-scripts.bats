#!/usr/bin/env bats
# The tips that the ghpkg packages print after installing.

setup() {
  repo=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  bin=$BATS_TEST_TMPDIR/bin
  mkdir -p "$bin"
  for tool in sh echo; do ln -s "$(command -v $tool)" "$bin/$tool"; done
}

tips() { PATH=$bin sh -c ". '$1' && post_install"; }

@test "both install scripts are the same apart from their header" {
  diff <(tail -n +2 "$repo/packaging/ghpkg.install") <(tail -n +2 "$repo/packaging/ghpkg-gh/ghpkg-gh.install")
}

@test "the login tip shows when gh isn't installed" {
  run tips "$repo/packaging/ghpkg.install"
  [[ $output == *"install github-cli"*"gh auth login"* ]]
}

@test "the login tip stays quiet when gh is installed" {
  printf '#!/bin/sh\n' > "$bin/gh"; chmod +x "$bin/gh"
  run tips "$repo/packaging/ghpkg.install"
  [[ $output != *"gh auth login"* ]]
}
