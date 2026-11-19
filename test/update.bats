#!/usr/bin/env bats
# update and remove, with makepkg, pacman and sudo faked.

load helpers

setup() {
  setup_ghpkg
  export GHPKG_TEST_SUDO=ok
}

pkgbuild() { cat "$GHPKG_ROOT/$1/PKGBUILD"; }

@test "update sets pkgver, resets pkgrel and takes GitHub's checksum" {
  make_pkgbuild app-gh me/app 1.0
  sed -i 's/^pkgrel=1/pkgrel=3/' "$GHPKG_ROOT/app-gh/PKGBUILD"
  installed app-gh 1.0-3
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst cafe01

  run ghpkg update
  [[ $status -eq 0 ]]
  grep -qx 'pkgver=1.1' "$GHPKG_ROOT/app-gh/PKGBUILD"
  grep -qx 'pkgrel=1' "$GHPKG_ROOT/app-gh/PKGBUILD"
  grep -qx "sha256sums=('cafe01')" "$GHPKG_ROOT/app-gh/PKGBUILD"
  grep -q -- '--syncdeps --install' "$GHPKG_TEST_LOG/makepkg"
  grep -qx 'app-gh 1.1-1' "$GHPKG_TEST_DB/installed"
  [[ $output == *"Updated: app-gh"* ]]
}

@test "a failed hash leaves the PKGBUILD unchanged, so the next update works" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst -
  cp "$GHPKG_ROOT/app-gh/PKGBUILD" "$BATS_TEST_TMPDIR/before"

  GHPKG_TEST_UPDPKGSUMS=fail run ghpkg update
  [[ $status -eq 1 ]]
  [[ $output == *"couldn't hash the download, so the PKGBUILD is unchanged"* ]]
  cmp "$GHPKG_ROOT/app-gh/PKGBUILD" "$BATS_TEST_TMPDIR/before"
  [[ ! -e $GHPKG_ROOT/app-gh/.PKGBUILD.ghpkg-new ]]
  [[ ! -s $GHPKG_TEST_LOG/makepkg ]]

  run ghpkg update
  [[ $status -eq 0 ]]
  grep -qx 'pkgver=1.1' "$GHPKG_ROOT/app-gh/PKGBUILD"
  grep -qx "sha256sums=('hash-of-the-download')" "$GHPKG_ROOT/app-gh/PKGBUILD"
  grep -qx 'app-gh 1.1-1' "$GHPKG_TEST_DB/installed"
}

@test "with no checksum from GitHub it hashes the download and warns" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst -

  run ghpkg update
  [[ $status -eq 0 ]]
  [[ $output == *"GitHub lists no checksum"* ]]
  grep -qx "sha256sums=('hash-of-the-download')" "$GHPKG_ROOT/app-gh/PKGBUILD"
  [[ -s $GHPKG_TEST_LOG/updpkgsums ]]
}

@test "a 'name::url' source is matched by its URL" {
  make_pkgbuild svc-gh me/svc 0.1 'svc-$pkgver.deb::$url/releases/download/v$pkgver/svc_amd64.deb'
  installed svc-gh 0.1-1
  serve_release me/svc v0.2 svc_amd64.deb beef02

  run ghpkg update
  [[ $status -eq 0 ]]
  grep -qx "sha256sums=('beef02')" "$GHPKG_ROOT/svc-gh/PKGBUILD"
}

@test "up-to-date packages are left alone" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.0

  run ghpkg update
  [[ $status -eq 0 ]]
  [[ $output == *"app-gh 1.0-1 is up to date"* ]]
  [[ ! -s $GHPKG_TEST_LOG/makepkg ]]
}

@test "without a terminal for sudo, update stops before changing anything" {
  unset GHPKG_TEST_SUDO
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst cafe01

  run ghpkg update </dev/null
  [[ $status -eq 1 ]]
  [[ $output == *"no terminal to ask in. Run 'ghpkg update' in a terminal."* ]]
  grep -qx 'pkgver=1.0' "$GHPKG_ROOT/app-gh/PKGBUILD"
  [[ ! -s $GHPKG_TEST_LOG/makepkg ]]

  # Named packages are repeated in the command to run.
  run ghpkg update app-gh </dev/null
  [[ $status -eq 1 ]]
  [[ $output == *"Run 'ghpkg update app-gh' in a terminal."* ]]
}

@test "without a terminal, an up-to-date run still succeeds" {
  unset GHPKG_TEST_SUDO
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.0
  run ghpkg update </dev/null
  [[ $status -eq 0 ]]
}

@test "a failed build after a bump says the PKGBUILD changed" {
  export GHPKG_TEST_MAKEPKG_FAIL=1
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst cafe01

  run ghpkg update
  [[ $status -eq 1 ]]
  [[ $output == *"Its PKGBUILD now says 1.1-1"* ]]
  [[ $output == *"Failed: app-gh"* ]]
}

@test "a failed first install doesn't claim the PKGBUILD changed" {
  export GHPKG_TEST_MAKEPKG_FAIL=1
  make_pkgbuild app-gh me/app 1.0
  serve_release me/app v1.0

  run ghpkg update app-gh
  [[ $status -eq 1 ]]
  [[ $output != *"PKGBUILD now says"* ]]
  [[ $output == *"Run 'ghpkg update app-gh' to retry."* ]]
}

@test "naming a package that isn't installed installs it" {
  make_pkgbuild app-gh me/app 1.0
  serve_release me/app v1.0
  run ghpkg update app-gh
  [[ $status -eq 0 ]]
  grep -qx 'app-gh 1.0-1' "$GHPKG_TEST_DB/installed"
}

@test "with no names, packages that aren't installed are skipped" {
  make_pkgbuild app-gh me/app 1.0
  serve_release me/app v1.0
  run ghpkg update
  [[ $status -eq 0 ]]
  [[ ! -s $GHPKG_TEST_LOG/makepkg ]]
}

@test "an unknown package name is refused" {
  run ghpkg update nope-gh
  [[ $status -eq 1 ]]
  [[ $output == *"no PKGBUILD for nope-gh"* ]]
}

@test "the cache keeps the new package and the one it replaced" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  mkdir -p "$GHPKG_CACHE/packages"
  : >"$GHPKG_CACHE/packages/app-gh-0.9-1-x86_64.pkg.tar.zst"
  : >"$GHPKG_CACHE/packages/app-gh-1.0-1-x86_64.pkg.tar.zst"
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst cafe01

  run ghpkg update
  [[ $status -eq 0 ]]
  [[ $(ls "$GHPKG_CACHE/packages" | paste -sd' ') == "app-gh-1.0-1-x86_64.pkg.tar.zst app-gh-1.1-1-x86_64.pkg.tar.zst" ]]
}

@test "the downloads are deleted after a successful install" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  serve_release me/app v1.1 app-gh-1.1.pkg.tar.zst cafe01
  mkdir -p "$GHPKG_CACHE/sources"
  : >"$GHPKG_CACHE/sources/app-gh-1.1.pkg.tar.zst"

  run ghpkg update
  [[ ! -e $GHPKG_CACHE/sources/app-gh-1.1.pkg.tar.zst ]]
}

@test "remove uninstalls with sudo pacman and keeps the PKGBUILD by default" {
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1

  run ghpkg remove app-gh </dev/null
  [[ $status -eq 0 ]]
  grep -qx 'sudo pacman -R app-gh' "$GHPKG_TEST_LOG/sudo"
  ! grep -q '^app-gh ' "$GHPKG_TEST_DB/installed"
  [[ -f $GHPKG_ROOT/app-gh/PKGBUILD ]]
  [[ $output == *"Kept $GHPKG_ROOT/app-gh"* ]]
}

@test "remove of a package that isn't installed only offers to delete the folder" {
  make_pkgbuild app-gh me/app 1.0
  run ghpkg remove app-gh </dev/null
  [[ $status -eq 0 ]]
  [[ $output == *"app-gh isn't installed."* ]]
  [[ ! -s $GHPKG_TEST_LOG/sudo ]]
}

@test "remove without a terminal for sudo refuses" {
  unset GHPKG_TEST_SUDO
  make_pkgbuild app-gh me/app 1.0
  installed app-gh 1.0-1
  run ghpkg remove app-gh </dev/null
  [[ $status -eq 1 ]]
  [[ $output == *"no terminal to ask in"* ]]
  grep -q '^app-gh ' "$GHPKG_TEST_DB/installed"
}

@test "a name that leads outside the packages folder is refused" {
  mkdir -p "$GHPKG_ROOT/../outside"
  echo 'pkgname=outside' >"$GHPKG_ROOT/../outside/PKGBUILD"

  run ghpkg remove ../outside <<<y
  [[ $status -eq 1 ]]
  [[ -f $GHPKG_ROOT/../outside/PKGBUILD ]]

  run ghpkg update ../outside
  [[ $status -eq 1 ]]
  [[ ! -s $GHPKG_TEST_LOG/makepkg ]]

  run ghpkg test-build ../outside
  [[ $status -eq 1 ]]
}
