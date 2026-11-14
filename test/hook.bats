#!/usr/bin/env bats
# hook: the Omarchy post-update hook, in a temporary home.

load helpers

setup() {
  setup_ghpkg
  export HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config
  mkdir -p "$XDG_CONFIG_HOME/omarchy"
  hooks=$XDG_CONFIG_HOME/omarchy/hooks/post-update.d
}

@test "install puts the report-only hook in place" {
  run ghpkg hook install
  [[ $status -eq 0 ]]
  cmp "$hooks/ghpkg-check-update.hook" "$REPO_DIR/integrations/omarchy/ghpkg-check-update.hook"
  [[ -x $hooks/ghpkg-check-update.hook ]]
  [[ $output == *"ends with a list"* ]]
}

@test "install --update swaps it for the hook that installs updates" {
  ghpkg hook install
  run ghpkg hook install --update
  [[ $status -eq 0 ]]
  [[ -x $hooks/ghpkg-update.hook && ! -e $hooks/ghpkg-check-update.hook ]]
  grep -qx 'ghpkg update' "$hooks/ghpkg-update.hook"
}

@test "status says which hook is installed, and when it's out of date" {
  run ghpkg hook status
  [[ $output == "Not installed."* ]]
  ghpkg hook install --update
  run ghpkg hook status
  [[ $output == "Installed: $hooks/ghpkg-update.hook" ]]
  echo '# changed' >>"$hooks/ghpkg-update.hook"
  run ghpkg hook status
  [[ $output == *"differs from this ghpkg's copy: run 'ghpkg hook install --update'"* ]]
}

@test "remove takes either hook out" {
  ghpkg hook install
  run ghpkg hook remove
  [[ $status -eq 0 && ! -e $hooks/ghpkg-check-update.hook ]]
  run ghpkg hook remove
  [[ $output == "No ghpkg hook was installed." ]]
}

@test "outside Omarchy, install refuses" {
  [[ ! -x /usr/bin/omarchy ]] || skip "this machine runs Omarchy, so there's no PATH without it"
  rm -rf "$XDG_CONFIG_HOME/omarchy"
  run env PATH="$REPO_DIR/test/stubs:/usr/bin" "$REPO_DIR/bin/ghpkg" hook install
  [[ $status -eq 1 && $output == *"doesn't look like an Omarchy system"* ]]
}

@test "the hooks run ghpkg and nothing else" {
  grep -qx 'ghpkg check-update' "$REPO_DIR/integrations/omarchy/ghpkg-check-update.hook"
  grep -qx 'ghpkg update' "$REPO_DIR/integrations/omarchy/ghpkg-update.hook"
}
