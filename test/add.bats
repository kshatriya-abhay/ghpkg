#!/usr/bin/env bats
# add, driven through a pseudo-terminal (`script`), the way a person runs it.
# The release is served by the fake curl; the test build uses the real makepkg.

load helpers

setup() {
  setup_ghpkg
  command -v script >/dev/null || skip "needs script (util-linux)"
  command -v makepkg >/dev/null && command -v fakeroot >/dev/null || skip "needs makepkg and fakeroot"
  (( EUID != 0 )) || skip "makepkg won't run as root"
  use_real_makepkg
  fake_hicolor
  echo "/usr/lib/libc.so.6 glibc" >>"$GHPKG_TEST_DB/owners"
  echo '{"name":"MyApp","description":"An app","license":{"spdx_id":"MIT"}}' |
    serve https://api.github.com/repos/me/myapp
  # The AUR: "myapp" is this app (its homepage is the repo); "myapp-bin" isn't.
  echo '{"results":[
    {"Name":"myapp","Description":"The same app","URL":"https://github.com/me/myapp"},
    {"Name":"myapp-bin","Description":"Another app entirely","URL":"https://example.com/other"}]}' |
    serve_aur "$(cat)" myapp other-name
}

# answers line... : runs `ghpkg add me/myapp` with those lines typed in.
add_with() {
  # The time limit ends a run that waits on a question the test has no answer for.
  run timeout 60 script -qefc "$REPO_DIR/bin/ghpkg add me/myapp" /dev/null < <(printf '%s\n' "$@")
}

pkgbuild() { cat "$GHPKG_ROOT/myapp-gh/PKGBUILD"; }

@test "add writes a PKGBUILD that test-builds, from the user's answers" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"

  # name, AUR conflicts, dependencies, optional dependencies, save, install now
  add_with "" y y y "" n
  [[ $status -eq 0 ]]
  [[ $output == *"Files: the same 3 files as myapp-1.0-1-x86_64.pkg.tar.zst."* ]]
  [[ $output == *"Install it when you're ready with: ghpkg update myapp-gh"* ]]

  run pkgbuild
  [[ $output == *"pkgname=myapp-gh"* ]]
  [[ $output == *"_ghrepo=me/myapp"* ]]
  [[ $output == *"pkgver=1.0"* ]]
  [[ $output == *'pkgdesc="A test app (from the upstream GitHub release)"'* ]]
  [[ $output == *"depends=('glibc' 'gtk3')"* ]]
  [[ $output == *"optdepends=('alsa-lib: sound')"* ]]
  [[ $output == *"provides=('myapp' 'myapp-core')"* ]]
  [[ $output == *"conflicts=('myapp' 'myapp-legacy')"* ]]
  [[ $output == *'_file="myapp-$pkgver-1-x86_64.pkg.tar.zst"'* ]]
  [[ $output == *'source=("$url/releases/download/v$pkgver/$_file")'* ]]
  [[ $output != *"install="* ]]
  [[ ! -s $GHPKG_TEST_LOG/sudo ]]
}

@test "an unrelated AUR package that only shares a name isn't added to conflicts" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  add_with "" y y y "" n
  [[ $output == *"myapp  [same GitHub repo] The same app"* ]]
  [[ $output == *"myapp-bin  Another app entirely"* ]]
  [[ $(grep '^conflicts=' "$GHPKG_ROOT/myapp-gh/PKGBUILD") != *myapp-bin* ]]
}

@test "upstream's name is left out of provides and conflicts when another app owns it" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  serve_aur '{"results":[{"Name":"myapp","Description":"Another app","URL":"https://github.com/someone/else"}]}' myapp
  # name, AUR conflicts, dependencies, optional dependencies, go on after the warning, save, install now
  add_with "" y y y y "" n
  [[ $output == *"These names belong to other apps: myapp (AUR"* ]]
  [[ $(grep '^provides=' "$GHPKG_ROOT/myapp-gh/PKGBUILD") == "provides=('myapp-core')" ]]
  [[ $(grep '^conflicts=' "$GHPKG_ROOT/myapp-gh/PKGBUILD") == "conflicts=('myapp-legacy')" ]]
}

@test "dependencies come from linked libraries too, and 'u' keeps upstream's only" {
  echo "/usr/lib/libcurl.so.4 libcurl-thing" >>"$GHPKG_TEST_DB/owners"
  FIXTURE_PROGRAM=/usr/bin/curl make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"

  add_with "" y u y "" n
  [[ $output == *"libcurl-thing  (a linked library)"* ]]
  [[ $output == *"gtk3  (upstream's list)  not installed: installing would pull it in"* ]]
  [[ $(grep '^depends=' "$GHPKG_ROOT/myapp-gh/PKGBUILD") == "depends=('glibc' 'gtk3')" ]]
}

@test "dependencies can be edited in the user's editor" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  printf '#!/bin/sh\nprintf "gtk3\\nwayland\\n" >"$1"\n' >"$BATS_TEST_TMPDIR/editor"
  chmod +x "$BATS_TEST_TMPDIR/editor"
  export EDITOR=$BATS_TEST_TMPDIR/editor

  add_with "" y e y "" n
  [[ $(grep '^depends=' "$GHPKG_ROOT/myapp-gh/PKGBUILD") == "depends=('gtk3' 'wayland')" ]]
}

@test "an .INSTALL is carried over only when the user says so" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0 with-install
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"

  # name, conflicts, deps, optdeps, carry the .INSTALL over, save, install now
  add_with "" y y y y "" n
  [[ $status -eq 0 ]]
  grep -qx 'install=myapp-gh.install' "$GHPKG_ROOT/myapp-gh/PKGBUILD"
  grep -q 'sh /usr/share/myapp/setup.sh' "$GHPKG_ROOT/myapp-gh/myapp-gh.install"
}

@test "stopping at the root-script question writes nothing" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0 with-install
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  add_with "" y y y s
  [[ $status -eq 0 ]]
  [[ $output == *"Stopped. Nothing was written."* ]]
  [[ ! -e $GHPKG_ROOT/myapp-gh ]]
}

@test "a name taken on the AUR is refused and asked again" {
  echo '{"results":[{"Name":"myapp-gh","Description":"Someone else","URL":null}]}' |
    serve_aur "$(cat)" myapp other-name
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  # first name (taken), second name, AUR conflicts: none, deps, optdeps, save, install now
  add_with "" myapp-mine n y y "" n
  [[ $status -eq 0 ]]
  [[ $output == *"myapp-gh is taken on the AUR"* ]]
  [[ ! -e $GHPKG_ROOT/myapp-gh ]]
  grep -qx 'pkgname=myapp-mine' "$GHPKG_ROOT/myapp-mine/PKGBUILD"
}

@test "the official repos having it means asking first; 'n' stops" {
  echo "extra myapp 2.0-1" >>"$GHPKG_TEST_DB/repo"
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  add_with n
  [[ $status -eq 0 ]]
  [[ $output == *"The official repos have it. Package it from GitHub anyway?"* ]]
  [[ $(ls -A "$GHPKG_ROOT") == "" ]]
}

@test "a release with only a .deb points to the agent skill" {
  make_deb "$BATS_TEST_TMPDIR/myapp_1.0_amd64.deb" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp_1.0_amd64.deb"
  add_with
  [[ $status -eq 1 ]]
  [[ $output == *"only a .deb"*"ghpkg skill install"* ]]
}

@test "add without a terminal refuses and points agents to the skill" {
  run ghpkg add me/myapp </dev/null
  [[ $status -eq 1 ]]
  [[ $output == *"needs a terminal"*"use the ghpkg skill"* ]]
}

@test "a file name without the version gets a versioned local name" {
  make_zst "$BATS_TEST_TMPDIR/myapp-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-x86_64.pkg.tar.zst"
  add_with "" y y y "" n
  [[ $status -eq 0 ]]
  grep -qx '_file="myapp-gh-$pkgver.pkg.tar.zst"' "$GHPKG_ROOT/myapp-gh/PKGBUILD"
  grep -qx 'source=("$_file::$url/releases/download/v$pkgver/myapp-x86_64.pkg.tar.zst")' "$GHPKG_ROOT/myapp-gh/PKGBUILD"
  [[ $output == *"Files: the same 3 files"* ]]
}

@test "suggest_name drops -git and -bin, and uses the repo for reverse-DNS names" {
  load_lib
  [[ $(suggest_name nbfc-linux-git nbfc-linux) == nbfc-linux-gh ]]
  [[ $(suggest_name omarchy-flux flux) == omarchy-flux-gh ]]
  [[ $(suggest_name ai.storyteller.photocraft photocraft) == photocraft-gh ]]
  [[ $(suggest_name "" MyApp) == myapp-gh ]]
}

@test "bash_array quotes items and goes multi-line when long" {
  load_lib
  [[ $(printf 'a\nb c\n' | bash_array) == "'a' 'b c'" ]]
  [[ $(printf "it's\n" | bash_array) == "'it'\\''s'" ]]
  long=$(printf 'package-number-%s\n' 1 2 3 4 5 | bash_array)
  [[ $long == $'\n'"  'package-number-1'"* ]]
}
