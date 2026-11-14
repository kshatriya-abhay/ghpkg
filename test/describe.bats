#!/usr/bin/env bats
# describe: downloading, checking and reading a release file.

load helpers

setup() {
  setup_ghpkg
  load_lib
  fake_hicolor
  echo "/usr/lib/libc.so.6 glibc" >>"$GHPKG_TEST_DB/owners"
}

describe_json_of() { describe "$@" --json; }

@test "a .pkg.tar.zst: metadata, files and libraries" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"

  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $status -eq 0 ]]
  json=$output
  [[ $(jq -r '.file.kind, .file.verified, .metadata.name, .metadata.version' <<<"$json" | paste -sd' ') == "pkg true myapp 1.0-1" ]]
  [[ $(jq -c '.metadata.depends' <<<"$json") == '["glibc","gtk3"]' ]]
  [[ $(jq -c '.metadata.optdepends' <<<"$json") == '["alsa-lib: sound"]' ]]
  [[ $(jq -r '.metadata.dependency_names' <<<"$json") == arch ]]
  [[ $(jq -c '.files.programs' <<<"$json") == '["usr/bin/myapp"]' ]]
  [[ $(jq -c '.files.desktop' <<<"$json") == '["usr/share/applications/myapp.desktop"]' ]]
  [[ $(jq -c '.scripts' <<<"$json") == '[]' ]]
  [[ $(jq -c '[.libraries.needed[] | {lib, owner}]' <<<"$json") == '[{"lib":"libc.so.6","owner":"glibc"}]' ]]
}

@test "programs that link only to libc get the runtime-libraries warning" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  run describe me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $output == *"link only to the basic C libraries"* ]]
}

@test "an .INSTALL is shown in full, with the scripts it calls" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0 with-install
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"

  run describe me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $status -eq 0 ]]
  [[ $output == *"--- .INSTALL ---"* ]]
  [[ $output == *"sh /usr/share/myapp/setup.sh"* ]]
  [[ $output == *"--- /usr/share/myapp/setup.sh (called by the above) ---"* ]]
  [[ $output == *'echo "setting up"'* ]]
  [[ $output == *"Has scripts that run as root"* ]]
}

@test "a .deb: Debian dependencies, maintainer scripts and layout warnings" {
  make_deb "$BATS_TEST_TMPDIR/myapp_1.0_amd64.deb" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp_1.0_amd64.deb"

  run describe_json_of me/myapp myapp_1.0_amd64.deb
  [[ $status -eq 0 ]]
  json=$output
  [[ $(jq -r '.file.kind, .metadata.name, .metadata.version, .metadata.description, .metadata.url' <<<"$json" | paste -sd'|') == "deb|myapp|1.0|A test app|https://example.org/myapp" ]]
  [[ $(jq -c '.metadata.depends' <<<"$json") == '["libc6 (>= 2.31)","libgtk-3-0 | libgtk-4-1","libnss3"]' ]]
  [[ $(jq -c '.metadata.optdepends' <<<"$json") == '["libasound2"]' ]]
  [[ $(jq -c '[.scripts[].name]' <<<"$json") == '["postinst"]' ]]
  [[ $(jq -c '.files.setuid' <<<"$json") == '["opt/App Name/chrome-sandbox"]' ]]

  warnings=$(jq -r '.warnings[]' <<<"$json")
  [[ $warnings == *"Debian package names"* ]]
  [[ $warnings == *"Programs are in /opt"* ]]
  [[ $warnings == *"setuid"*"opt/App Name/chrome-sandbox"* ]]
  [[ $warnings == *"/usr/share/doc"* ]]
  [[ $warnings == *"Icon folders the hicolor theme doesn't know"*"huge/apps"* ]]
  [[ $warnings != *"256x256@2"* ]]
}

@test "a download that doesn't match GitHub's checksum is deleted and refused" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  serve https://github.com/me/myapp/releases/download/v1.0/myapp-1.0-1-x86_64.pkg.tar.zst \
    <"$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  serve_release me/myapp v1.0 myapp-1.0-1-x86_64.pkg.tar.zst 0000000000000000

  run describe me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $status -eq 1 ]]
  [[ $output == *"doesn't match GitHub's checksum"* ]]
  [[ ! -e $GHPKG_CACHE/sources/myapp-1.0-1-x86_64.pkg.tar.zst ]]
}

@test "a file GitHub lists no checksum for is marked unverified" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  serve https://github.com/me/myapp/releases/download/v1.0/myapp-1.0-1-x86_64.pkg.tar.zst \
    <"$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  serve_release me/myapp v1.0 myapp-1.0-1-x86_64.pkg.tar.zst -

  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $status -eq 0 ]]
  [[ $(jq -r .file.verified <<<"$output") == false ]]
  [[ $(jq -r '.warnings[0]' <<<"$output") == *"can't be verified"* ]]
}

@test "a good copy in the cache isn't downloaded again" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  describe me/myapp myapp-1.0-1-x86_64.pkg.tar.zst >/dev/null
  describe me/myapp myapp-1.0-1-x86_64.pkg.tar.zst >/dev/null
  [[ $(grep -c 'releases/download' "$GHPKG_TEST_LOG/curl") -eq 1 ]]
}

@test "describe refuses files that aren't a .pkg.tar.zst or .deb" {
  serve_release me/myapp v1.0 myapp-1.0-linux-x86_64.tar.gz aaa
  run describe me/myapp myapp-1.0-linux-x86_64.tar.gz
  [[ $status -eq 1 && $output == *"isn't a .pkg.tar.zst or .deb"* ]]
}

@test "describe of a file the release doesn't have fails clearly" {
  serve_release me/myapp v1.0 myapp-1.0-x86_64.pkg.tar.zst aaa
  run describe me/myapp myapp-2.0-x86_64.pkg.tar.zst
  [[ $status -eq 1 && $output == *"has no file named myapp-2.0-x86_64.pkg.tar.zst"* ]]
}

@test "the readable output names what needs a decision" {
  make_deb "$BATS_TEST_TMPDIR/myapp_1.0_amd64.deb" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp_1.0_amd64.deb"
  run describe me/myapp myapp_1.0_amd64.deb
  [[ $status -eq 0 ]]
  [[ $output == *"Dependencies (Debian names):"* ]]
  [[ $output == *"--- postinst ---"* ]]
  [[ $output == *"Needs a decision:"* ]]
}
