#!/usr/bin/env bats
# ghpkg's own packaging: the release package builds and runs from /usr, and
# ghpkg-gh can track it like any other package.

load helpers

setup_file() {
  command -v makepkg >/dev/null && command -v fakeroot >/dev/null || skip "needs makepkg and fakeroot"
  (( EUID != 0 )) || skip "makepkg won't run as root"
  # Build the release package once, from a copy of the checkout.
  export RELEASE_DIR=$BATS_FILE_TMPDIR/release
  mkdir -p "$RELEASE_DIR"
  local src=$BATS_FILE_TMPDIR/checkout
  mkdir -p "$src"
  (cd "$BATS_TEST_DIRNAME/.." && git ls-files -co --exclude-standard | grep -v '^packaging/out/' | xargs -d '\n' cp --parents -t "$src")
  (cd "$src/packaging" && PKGDEST=$RELEASE_DIR makepkg --nodeps --noconfirm --clean >"$BATS_FILE_TMPDIR/makepkg.log" 2>&1)
}

setup() {
  setup_ghpkg
  release=$(find "$RELEASE_DIR" -name 'ghpkg-*-any.pkg.tar.zst' | head -1)
  [[ -n $release ]]
}

@test "the release package is named the way ghpkg-gh expects" {
  version=$(sed -n 's/^GHPKG_VERSION=//p' "$REPO_DIR/lib/common.sh")
  [[ ${release##*/} == "ghpkg-$version-1-any.pkg.tar.zst" ]]
  grep -qx "pkgver=$version" "$REPO_DIR/packaging/PKGBUILD"
}

@test "the release package holds the program, the libraries, the skill and the hooks" {
  files=$(bsdtar -tf "$release")
  for f in usr/bin/ghpkg usr/lib/ghpkg/common.sh usr/lib/ghpkg/add.sh \
    usr/share/ghpkg/skill/ghpkg/SKILL.md usr/share/ghpkg/skill/ghpkg/templates/PKGBUILD.zst \
    usr/share/ghpkg/integrations/omarchy/ghpkg-check-update.hook usr/share/licenses/ghpkg/LICENSE .INSTALL; do
    grep -qx "$f" <<<"$files" || { echo "missing $f"; false; }
  done
}

@test "installed under /usr, ghpkg finds its libraries and data" {
  root=$BATS_TEST_TMPDIR/installed
  mkdir -p "$root"
  bsdtar -xf "$release" -C "$root" usr
  run "$root/usr/bin/ghpkg" --version
  [[ $status -eq 0 && $output == "ghpkg $(sed -n 's/^GHPKG_VERSION=//p' "$REPO_DIR/lib/common.sh")" ]]
  run "$root/usr/bin/ghpkg" skill path
  [[ $output == "$root/usr/share/ghpkg/skill/ghpkg" ]]
}

@test "ghpkg-gh picks up a release, takes its checksum and builds the same files" {
  use_real_makepkg
  load_lib
  version=$(sed -n 's/^GHPKG_VERSION=//p' "$REPO_DIR/lib/common.sh")
  cp -r "$REPO_DIR/packaging/ghpkg-gh" "$GHPKG_ROOT/"
  publish kshatriya-abhay/ghpkg "v$version" "$release"
  mkdir -p "$GHPKG_CACHE/sources"
  cp "$release" "$GHPKG_CACHE/sources/"

  plan ghpkg-gh
  [[ $STATE == release && $LATEST == "$version" ]]
  bump ghpkg-gh
  grep -qx "pkgver=$version" "$GHPKG_ROOT/ghpkg-gh/PKGBUILD"
  grep -qx "sha256sums=('$(sha256sum "$release" | cut -d' ' -f1)')" "$GHPKG_ROOT/ghpkg-gh/PKGBUILD"

  run test_build ghpkg-gh
  [[ $status -eq 0 ]]
  [[ $output == *"... Passed"* ]]
  [[ $output == *"Files: the same "*" files as ${release##*/}."* ]]
}
