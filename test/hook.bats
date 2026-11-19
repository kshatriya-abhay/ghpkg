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

# ghpkg-gh owns this checkout's files, and a new release of it is out.
self_update_ready() {
  export GHPKG_TEST_SUDO=ok
  echo "$REPO_DIR/integrations/omarchy/ghpkg-update.hook ghpkg-gh" >>"$GHPKG_TEST_DB/owners"
  make_pkgbuild ghpkg-gh kshatriya-abhay/ghpkg 1.0
  installed ghpkg-gh 1.0-1
  serve_release kshatriya-abhay/ghpkg v1.1 ghpkg-gh-1.1.pkg.tar.zst cafe01
  mkdir -p "$hooks"
  echo '# from an older ghpkg' >"$hooks/ghpkg-check-update.hook"
}

@test "after ghpkg updates itself, an old hook is pointed out without a terminal" {
  self_update_ready
  run ghpkg update ghpkg-gh </dev/null
  [[ $status -eq 0 ]]
  [[ $output == *"came with an older ghpkg. Update it with: ghpkg hook install"* ]]
  [[ $output != *"install --update"* ]]
  grep -qx '# from an older ghpkg' "$hooks/ghpkg-check-update.hook"
}

@test "after ghpkg updates itself, saying yes replaces an old hook with the same kind" {
  self_update_ready
  mv "$hooks/ghpkg-check-update.hook" "$hooks/ghpkg-update.hook"
  run timeout 60 script -qefc "$REPO_DIR/bin/ghpkg update ghpkg-gh" /dev/null < <(printf 'y\n')
  [[ $status -eq 0 ]]
  [[ $output == *"Update it to this version's? [Y/n]"* ]]
  cmp "$hooks/ghpkg-update.hook" "$REPO_DIR/integrations/omarchy/ghpkg-update.hook"
  [[ -x $hooks/ghpkg-update.hook && ! -e $hooks/ghpkg-check-update.hook ]]
}

@test "updating another package doesn't mention the hook" {
  self_update_ready
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst cafe02
  run ghpkg update app-gh </dev/null
  [[ $status -eq 0 ]]
  [[ $output != *"older ghpkg"* ]]
}

@test "a hook that's already current isn't mentioned after a self-update" {
  self_update_ready
  cp "$REPO_DIR/integrations/omarchy/ghpkg-check-update.hook" "$hooks/"
  run ghpkg update ghpkg-gh </dev/null
  [[ $status -eq 0 ]]
  [[ $output != *"older ghpkg"* ]]
}
