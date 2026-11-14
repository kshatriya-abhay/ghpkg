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

  export PATH=$REPO_DIR/test/stubs:$PATH
  unset GITHUB_TOKEN GHPKG_TEST_GH_TOKEN GHPKG_TEST_SUDO GHPKG_TEST_OFFLINE GHPKG_TEST_MAKEPKG_FAIL
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
