#!/usr/bin/env bats
# test-build, with the real makepkg and fakeroot, offline: the release file is
# put in the cache first, so makepkg never downloads.

load helpers

setup() {
  setup_ghpkg
  command -v makepkg >/dev/null && command -v fakeroot >/dev/null || skip "needs makepkg and fakeroot"
  (( EUID != 0 )) || skip "makepkg won't run as root"
  use_real_makepkg
  mkdir -p "$GHPKG_CACHE/sources"
}

# A repack PKGBUILD for a test .pkg.tar.zst, written the way the template is.
zst_pkgbuild() {
  local file=$GHPKG_CACHE/sources/myapp-1.0-1-x86_64.pkg.tar.zst
  make_zst "$file" myapp 1.0
  mkdir -p "$GHPKG_ROOT/myapp-gh"
  cat >"$GHPKG_ROOT/myapp-gh/PKGBUILD" <<EOF
pkgname=myapp-gh
_ghrepo=me/myapp
pkgver=1.0
pkgrel=1
pkgdesc="A test app"
arch=(x86_64)
url="https://github.com/\$_ghrepo"
license=(MIT)
depends=(glibc gtk3)
provides=(myapp)
conflicts=(myapp)
options=(!strip !debug)
_file=myapp-\$pkgver-1-x86_64.pkg.tar.zst
source=("\$url/releases/download/v\$pkgver/\$_file")
noextract=("\$_file")
sha256sums=('$(sha256sum "$file" | cut -d' ' -f1)')

package() {
  bsdtar -xf "\$srcdir/\$_file" -C "\$pkgdir" \\
    --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL
}
EOF
}

@test "a .zst repack builds with the same files as the release file" {
  zst_pkgbuild
  installed glibc 2.44-1
  run ghpkg test-build myapp-gh
  [[ $status -eq 0 ]]
  [[ $output == *"checksum: myapp-1.0-1-x86_64.pkg.tar.zst ... Passed"* ]]
  [[ $output == *"myapp-gh 1.0-1"* ]]
  [[ $output == *"depends:   glibc gtk3"* ]]
  [[ $output == *"Files: the same 3 files as myapp-1.0-1-x86_64.pkg.tar.zst."* ]]
}

@test "test-build names the dependencies that aren't installed" {
  zst_pkgbuild
  installed glibc 2.44-1
  run ghpkg test-build myapp-gh
  [[ $output == *"installing would pull in: gtk3"* ]]
}

@test "test-build installs nothing and leaves the packages folder clean" {
  zst_pkgbuild
  run ghpkg test-build myapp-gh
  [[ $status -eq 0 ]]
  # makepkg reads with pacman -Qi; nothing may install, upgrade or remove.
  ! grep -qE "^pacman -(U|S|R)" "$GHPKG_TEST_LOG/pacman"
  [[ ! -s $GHPKG_TEST_LOG/sudo ]]
  [[ $(ls -A "$GHPKG_ROOT/myapp-gh") == PKGBUILD ]]
}

@test "a .deb build lists the files that differ from the release file" {
  local file=$GHPKG_CACHE/sources/myapp-1.0.deb
  make_deb "$file" myapp 1.0
  mkdir -p "$GHPKG_ROOT/myapp-gh"
  cat >"$GHPKG_ROOT/myapp-gh/PKGBUILD" <<EOF
pkgname=myapp-gh
_ghrepo=me/myapp
pkgver=1.0
pkgrel=1
arch=(x86_64)
url="https://github.com/\$_ghrepo"
options=(!strip !debug)
source=("myapp-\$pkgver.deb::\$url/releases/download/v\$pkgver/myapp_amd64.deb")
sha256sums=('$(sha256sum "$file" | cut -d' ' -f1)')

package() {
  bsdtar -xf "\$srcdir"/data.tar.* -C "\$pkgdir"
  rm -rf "\$pkgdir/usr/share/doc"
  mkdir -p "\$pkgdir/usr/bin"
  ln -s "/opt/App Name/myapp" "\$pkgdir/usr/bin/myapp"
}
EOF
  run ghpkg test-build myapp-gh
  [[ $status -eq 0 ]]
  [[ $output == *"only in the release file: /usr/share/doc/myapp/changelog.Debian"* ]]
  [[ $output == *"only in the build:        /usr/bin/myapp"* ]]
}

@test "a failed build shows the end of makepkg's log" {
  zst_pkgbuild
  sed -i "s/^sha256sums=.*/sha256sums=('0000')/" "$GHPKG_ROOT/myapp-gh/PKGBUILD"
  run ghpkg test-build myapp-gh
  [[ $status -eq 1 ]]
  [[ $output == *"FAILED"* ]]
  [[ $output == *"The build failed. The end of makepkg's log"* ]]
}
