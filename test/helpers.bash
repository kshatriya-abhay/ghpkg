# shellcheck shell=bash
# Shared setup for the bats tests. Every test gets its own packages folder,
# cache and fake system, and the stubs in test/stubs come first on PATH, so
# no test touches the network, sudo or the real packages folder.

REPO_DIR=$(cd "$BATS_TEST_DIRNAME/.." && pwd)

setup_ghpkg() {
  export GHPKG_ROOT=$BATS_TEST_TMPDIR/pkgbuilds
  export GHPKG_CACHE=$BATS_TEST_TMPDIR/cache
  export GHPKG_TEST_HTTP=$BATS_TEST_TMPDIR/http
  export GHPKG_TEST_DB=$BATS_TEST_TMPDIR/db
  export GHPKG_TEST_LOG=$BATS_TEST_TMPDIR/log
  mkdir -p "$GHPKG_ROOT" "$GHPKG_CACHE" "$GHPKG_TEST_HTTP" "$GHPKG_TEST_DB" "$GHPKG_TEST_LOG"
  touch "$GHPKG_TEST_DB"/{installed,repo,owners} "$GHPKG_TEST_LOG"/{curl,pacman,sudo,makepkg,updpkgsums}
  # The test packages depend on these, so the official repos have them.
  printf 'core glibc 2.44-1\nextra gtk3 1:3.24-1\n' >"$GHPKG_TEST_DB/repo"

  export PATH=$REPO_DIR/test/stubs:$PATH
  unset GITHUB_TOKEN GHPKG_TEST_GH_TOKEN GHPKG_TEST_SUDO GHPKG_TEST_OFFLINE GHPKG_TEST_MAKEPKG_FAIL
  # Tips go to stderr, which `run` mixes into $output. The tip tests turn them on.
  export GHPKG_NO_TIPS=1
}

# Loads lib/ for tests that call one function directly.
load_lib() {
  local lib
  for lib in "$REPO_DIR"/lib/*.sh; do
    # shellcheck disable=SC1090
    source "$lib"
  done
}

ghpkg() { "$REPO_DIR/bin/ghpkg" "$@"; }

# serve URL [HTTP status] < body: what the fake curl answers for URL.
serve() {
  local key
  key=$(printf '%s' "$1" | sha256sum | cut -c1-16)
  cat >"$GHPKG_TEST_HTTP/$key.body"
  echo "${2:-200}" >"$GHPKG_TEST_HTTP/$key.code"
}

# serve_aur json name...: what the AUR answers, for its exact-name lookup and
# for a name search on each given name.
serve_aur() {
  local json=$1 name
  shift
  serve https://aur.archlinux.org/rpc/v5/info <<<"$json"
  for name; do
    serve "https://aur.archlinux.org/rpc/v5/search/$name" <<<"$json"
  done
}

# serve_release owner/repo tag [asset-name digest]...: a latest release whose
# assets are the given names. A digest of "-" means GitHub lists none.
serve_release() {
  local repo=$1 tag=$2 assets='[]' name digest
  shift 2
  while (( $# )); do
    name=$1 digest=$2
    shift 2
    assets=$(jq --arg n "$name" --arg d "$digest" \
      --arg u "https://github.com/$repo/releases/download/$tag/$name" \
      '. + [{name: $n, size: 1000, browser_download_url: $u,
             digest: (if $d == "-" then null else "sha256:" + $d end)}]' <<<"$assets")
  done
  jq -n --arg tag "$tag" --argjson assets "$assets" \
    '{tag_name: $tag, published_at: "2026-11-01T00:00:00Z", prerelease: false, assets: $assets}' |
    serve "https://api.github.com/repos/$repo/releases/latest"
}

# make_pkgbuild name owner/repo version [source]: a minimal package folder.
make_pkgbuild() {
  local name=$1 repo=$2 version=$3
  local src=${4:-"\$url/releases/download/v\$pkgver/$name-\$pkgver.pkg.tar.zst"}
  mkdir -p "$GHPKG_ROOT/$name"
  cat >"$GHPKG_ROOT/$name/PKGBUILD" <<EOF
pkgname=$name
_ghrepo=$repo
pkgver=$version
pkgrel=1
arch=(x86_64)
url="https://github.com/\$_ghrepo"
source=("$src")
sha256sums=('old')
EOF
}

installed() { echo "$1 $2" >>"$GHPKG_TEST_DB/installed"; }

# --- Test packages ----------------------------------------------------------
# Small but real release files, built with bsdtar. Their programs are copies of
# /usr/bin/true: a real ELF file that links only to libc.

# make_zst file name version [with-install]: a pacman package. With a fourth
# argument it has an .INSTALL that calls a setup script inside the package.
# FIXTURE_PROGRAM picks another ELF file to use as its program.
make_zst() {
  local out=$1 name=$2 version=$3 with_install=${4:-} dir members=(.PKGINFO usr)
  dir=$BATS_TEST_TMPDIR/build-zst-$name
  rm -rf "$dir"
  mkdir -p "$dir/usr/bin" "$dir/usr/share/applications" "$dir/usr/share/icons/hicolor/256x256/apps"
  cp "${FIXTURE_PROGRAM:-/usr/bin/true}" "$dir/usr/bin/$name"
  printf '[Desktop Entry]\nName=%s\n' "$name" >"$dir/usr/share/applications/$name.desktop"
  : >"$dir/usr/share/icons/hicolor/256x256/apps/$name.png"
  cat >"$dir/.PKGINFO" <<PKGINFO
pkgname = $name
pkgver = $version-1
pkgdesc = A test app
url = https://example.org/$name
license = MIT
depend = glibc
depend = gtk3
optdepend = alsa-lib: sound
provides = $name-core
conflict = $name-legacy
PKGINFO
  if [[ -n $with_install ]]; then
    mkdir -p "$dir/usr/share/$name"
    printf '#!/bin/sh\necho "setting up"\n' >"$dir/usr/share/$name/setup.sh"
    printf 'post_install() {\n  sh /usr/share/%s/setup.sh\n}\n' "$name" >"$dir/.INSTALL"
    members=(.PKGINFO .INSTALL usr)
  fi
  (cd "$dir" && bsdtar --zstd -cf "$out" "${members[@]}")
}

# make_deb file name version: a .deb in Debian's layout, with the problems a
# PKGBUILD has to deal with: a program in /opt only, a setuid file, Debian
# docs, an unknown icon folder (next to a valid HiDPI one), a postinst script.
make_deb() {
  local out=$1 name=$2 version=$3 dir
  dir=$BATS_TEST_TMPDIR/build-deb-$name
  rm -rf "$dir"
  mkdir -p "$dir/data/opt/App Name" "$dir/data/usr/share/doc/$name" \
    "$dir/data/usr/share/icons/hicolor/256x256@2/apps" "$dir/data/usr/share/icons/hicolor/huge/apps" "$dir/control"
  cp /usr/bin/true "$dir/data/opt/App Name/$name"
  cp /usr/bin/true "$dir/data/opt/App Name/chrome-sandbox"
  chmod 4755 "$dir/data/opt/App Name/chrome-sandbox"
  echo changes >"$dir/data/usr/share/doc/$name/changelog.Debian"
  : >"$dir/data/usr/share/icons/hicolor/256x256@2/apps/$name.png"
  : >"$dir/data/usr/share/icons/hicolor/huge/apps/$name.png"
  cat >"$dir/control/control" <<CONTROL
Package: $name
Version: $version
Architecture: amd64
Depends: libc6 (>= 2.31), libgtk-3-0 | libgtk-4-1,
 libnss3
Recommends: libasound2
Homepage: https://example.org/$name
Description: A test app
 A longer description
 over two lines.
CONTROL
  printf '#!/bin/sh\nupdate-desktop-database || true\n' >"$dir/control/postinst"
  echo 2.0 >"$dir/debian-binary"
  (cd "$dir/data" && bsdtar -czf ../data.tar.gz .)
  (cd "$dir/control" && bsdtar -czf ../control.tar.gz .)
  (cd "$dir" && bsdtar --format=ar -cf "$out" debian-binary control.tar.gz data.tar.gz)
}

# unslash_dirs tar: stores a tar's folders as "usr/bin" instead of "usr/bin/",
# the way some .deb tools write them. bsdtar always adds the slash, so this
# edits the headers: only for a ustar file whose entries are all empty, so
# every 512-byte block is a header.
unslash_dirs() {
  local tar=$1 blocks i name sum
  blocks=$(( $(stat -c %s "$tar") / 512 ))
  for (( i = 0; i < blocks; i++ )); do
    name=$(dd if="$tar" bs=512 skip="$i" count=1 2>/dev/null | head -c 100 | tr -d '\0')
    [[ $name == */ ]] || continue
    printf '\0' | dd of="$tar" bs=1 seek=$(( i * 512 + ${#name} - 1 )) conv=notrunc 2>/dev/null
    # The header checksum is the sum of its bytes: the slash (47) is gone.
    sum=$(dd if="$tar" bs=1 skip=$(( i * 512 + 148 )) count=6 2>/dev/null)
    printf '%06o\0 ' $(( 8#$sum - 47 )) | dd of="$tar" bs=1 seek=$(( i * 512 + 148 )) conv=notrunc 2>/dev/null
  done
}

# publish owner/repo tag file...: serves the files as the latest release's
# assets, with GitHub listing each one's real checksum.
publish() {
  local repo=$1 tag=$2 file args=()
  shift 2
  for file; do
    serve "https://github.com/$repo/releases/download/$tag/${file##*/}" <"$file"
    args+=("${file##*/}" "$(sha256sum "$file" | cut -d' ' -f1)")
  done
  serve_release "$repo" "$tag" "${args[@]}"
}

# A hicolor index.theme that knows only a few folders, so icon checks don't
# depend on the machine running the tests.
fake_hicolor() {
  export HICOLOR_INDEX=$BATS_TEST_TMPDIR/index.theme
  printf '[Icon Theme]\nDirectories=256x256/apps,256x256@2/apps,scalable/apps\n' >"$HICOLOR_INDEX"
}

# Takes the fake makepkg off PATH, for tests that run the real one.
use_real_makepkg() {
  local dir=$BATS_TEST_TMPDIR/stubs-no-makepkg
  mkdir -p "$dir"
  cp "$REPO_DIR"/test/stubs/* "$dir/"
  rm "$dir/makepkg"
  export PATH=$dir:${PATH#"$REPO_DIR/test/stubs:"}
}
