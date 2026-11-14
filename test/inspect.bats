#!/usr/bin/env bats
# inspect: ranking release files and checking names.

load helpers

setup() {
  setup_ghpkg
  load_lib
  echo '{"name":"MyApp","description":"An app","license":{"spdx_id":"MIT"}}' |
    serve https://api.github.com/repos/me/myapp
  echo '{"results":[{"Name":"myapp"},{"Name":"myapp-bin"}]}' | serve https://aur.archlinux.org/rpc/v5/info
}

@test "parse_repo accepts owner/repo and GitHub URLs" {
  [[ $(parse_repo me/myapp) == me/myapp ]]
  [[ $(parse_repo https://github.com/me/myapp) == me/myapp ]]
  [[ $(parse_repo https://github.com/me/myapp/releases/tag/v1.0) == me/myapp ]]
  [[ $(parse_repo github.com/me/myapp.git) == me/myapp ]]
  run parse_repo myapp
  [[ $status -ne 0 ]]
  run parse_repo 'me/my app'
  [[ $status -ne 0 ]]
}

@test "asset_kind ranks packages first and skips other platforms and extras" {
  [[ $(asset_kind app-1.0-1-x86_64.pkg.tar.zst) == "1 pkg" ]]
  [[ $(asset_kind app_1.0_amd64.deb) == "2 deb" ]]
  [[ $(asset_kind app-1.0-linux-x86_64.tar.gz) == "3 tarball" ]]
  [[ $(asset_kind app-1.0-x86_64.AppImage) == "4 appimage" ]]
  [[ $(asset_kind app-1.0.x86_64.rpm) == "5 rpm" ]]
  for skipped in app-1.0-x86_64.pkg.tar.zst.sig app-1.0-aarch64.pkg.tar.zst app_arm64.deb \
    app-macos-universal.dmg app-windows-x64.msi app-freebsd-x86_64.tar.gz app.AppImage.zsync \
    SHA256SUMS.txt app-debug-1.0-1-x86_64.pkg.tar.zst app-1.0-aur.tar.gz app-ios-1.0.ipa; do
    [[ -z $(asset_kind "$skipped") ]] || { echo "not skipped: $skipped"; false; }
  done
}

@test "inspect lists usable files best first, with checksums" {
  serve_release me/myapp v1.0 \
    myapp_1.0_amd64.deb aaa myapp-1.0-x86_64.pkg.tar.zst bbb myapp-1.0-aarch64.pkg.tar.zst ccc \
    myapp-1.0.AppImage - myapp-1.0-x86_64.pkg.tar.zst.sig ddd
  run inspect me/myapp
  [[ $status -eq 0 ]]
  [[ $output == *"1. myapp-1.0-x86_64.pkg.tar.zst  [Arch package, 1 KB, checksum on GitHub]"* ]]
  [[ $output == *"2. myapp_1.0_amd64.deb  [.deb, 1 KB, checksum on GitHub]"* ]]
  [[ $output == *"3. myapp-1.0.AppImage  [AppImage, 1 KB, no checksum on GitHub]"* ]]
  [[ $output != *aarch64* && $output != *.sig* ]]
  [[ $output == *"Next: ghpkg describe me/myapp myapp-1.0-x86_64.pkg.tar.zst"* ]]
}

@test "inspect reports AUR names, the official repos and the suggested name" {
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst bbb
  run inspect me/myapp
  [[ $output == *"AUR: myapp taken, myapp-bin taken, myapp-git free, myapp-gh free"* ]]
  [[ $output == *"Official repos: nothing named myapp."* ]]
  [[ $output == *"Suggested name: myapp-gh"* ]]
  [[ $output == *"Not set up in your packages yet."* ]]
}

@test "inspect says to use the official package when there is one" {
  echo "extra myapp 2.0-1" >>"$GHPKG_TEST_DB/repo"
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst bbb
  run inspect me/myapp
  [[ $output == *"Official repos: extra/myapp 2.0-1. Install that instead."* ]]
  [[ $output != *"Suggested name"* ]]
}

@test "inspect warns when the suggested name is taken on the AUR" {
  echo '{"results":[{"Name":"myapp-gh"}]}' | serve https://aur.archlinux.org/rpc/v5/info
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst bbb
  run inspect me/myapp
  [[ $output == *"Suggested name myapp-gh is taken on the AUR: pick another."* ]]
}

@test "inspect notices an existing PKGBUILD for the repo" {
  make_pkgbuild myapp-gh me/myapp 1.0
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst bbb
  run inspect me/myapp
  [[ $output == *"Already set up as: myapp-gh."* ]]
}

@test "inspect copes with the AUR being unreachable" {
  rm "$GHPKG_TEST_HTTP"/*
  echo '{"name":"MyApp","description":"An app","license":null}' | serve https://api.github.com/repos/me/myapp
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst bbb
  run inspect me/myapp
  [[ $status -eq 0 ]]
  [[ $output == *"AUR: couldn't be reached."* ]]
}

@test "inspect --json is valid JSON with the files and names" {
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst bbb
  run inspect me/myapp --json
  [[ $status -eq 0 ]]
  [[ $(jq -r '.files[0].kind, .release.version, .aur["myapp-gh"], .suggested_name' <<<"$output" | paste -sd' ') == "pkg 1.0 false myapp-gh" ]]
}

@test "inspect of a repo that doesn't exist fails clearly" {
  run inspect me/nothing
  [[ $status -eq 1 && $output == *"me/nothing: not found on GitHub"* ]]
}

@test "inspect says how to write the tag in source=" {
  serve_release me/myapp v1.0 myapp-1.0-1-x86_64.pkg.tar.zst cafe01
  run inspect me/myapp
  [[ $output == *'Download links use the tag v1.0: write it in source= as v$pkgver.'* ]]
  serve_release me/myapp 1.0 myapp-1.0-1-x86_64.pkg.tar.zst cafe01
  run inspect me/myapp
  [[ $output == *'Download links use the tag 1.0: write it in source= as $pkgver.'* ]]
}

@test "inspect warns when a package with the suggested name is installed without a PKGBUILD here" {
  serve_release me/myapp v1.0 myapp-1.0-1-x86_64.pkg.tar.zst cafe01
  installed myapp-gh 0.9-1
  run inspect me/myapp
  [[ $output == *"But myapp-gh 0.9-1 is installed"* ]]
  make_pkgbuild myapp-gh me/myapp 0.9
  run inspect me/myapp
  [[ $output != *"But myapp-gh"* ]]
}
