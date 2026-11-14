#!/usr/bin/env bats
# GitHub requests: the token, errors people can act on, and checksums.

load helpers

setup() {
  setup_ghpkg
  load_lib
}

@test "requests carry the gh login's token when there is one" {
  export GHPKG_TEST_GH_TOKEN=tok123
  serve_release me/app v1.0
  fetch_release me/app
  grep -q 'Authorization: Bearer tok123' "$GHPKG_TEST_LOG/curl"
}

@test "GITHUB_TOKEN wins over the gh login" {
  export GITHUB_TOKEN=fromenv GHPKG_TEST_GH_TOKEN=fromgh
  serve_release me/app v1.0
  fetch_release me/app
  grep -q 'Bearer fromenv' "$GHPKG_TEST_LOG/curl"
  ! grep -q fromgh "$GHPKG_TEST_LOG/curl"
}

@test "without any token, requests still work and carry no Authorization" {
  serve_release me/app v1.0
  fetch_release me/app
  [[ $(jq -r .tag_name <<<"$RELEASE") == v1.0 ]]
  ! grep -q Authorization "$GHPKG_TEST_LOG/curl"
}

@test "a used-up rate limit says how to fix it" {
  echo '{"message":"API rate limit exceeded for 1.2.3.4."}' |
    serve https://api.github.com/repos/me/app/releases/latest 403
  run fetch_release me/app
  [[ $status -ne 0 ]]
  fetch_release me/app || true
  [[ $GH_ERROR == *"rate limit"*"gh auth login"* ]]
}

@test "a missing repo or release says 'not found'" {
  fetch_release me/nothing || true
  [[ $GH_ERROR == "not found on GitHub" ]]
}

@test "no network says GitHub couldn't be reached" {
  export GHPKG_TEST_OFFLINE=1
  fetch_release me/app || true
  [[ $GH_ERROR == "couldn't reach GitHub" ]]
}

@test "asset_digest returns GitHub's checksum, or nothing" {
  serve_release me/app v1.0 app-1.0.pkg.tar.zst aaa111 app-1.0.deb -
  fetch_release me/app
  [[ $(asset_digest https://github.com/me/app/releases/download/v1.0/app-1.0.pkg.tar.zst) == aaa111 ]]
  [[ -z $(asset_digest https://github.com/me/app/releases/download/v1.0/app-1.0.deb) ]]
  [[ -z $(asset_digest https://github.com/me/app/releases/download/v1.0/missing) ]]
}
