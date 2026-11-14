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

@test "AUR packages whose homepage is the same repo are named; one that only shares a name isn't" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  echo '{"results":[
    {"Name":"myapp-bin","Description":"The same app","URL":"https://github.com/Me/MyApp/"},
    {"Name":"myapp","Description":"Another app entirely","URL":"https://example.com/other"}]}' |
    serve_aur "$(cat)" myapp other-name

  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $status -eq 0 ]]
  [[ $(jq -c '[.aur_same_app[].Name]' <<<"$output") == '["myapp-bin"]' ]]
  run describe me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $output == *"AUR packages of this same app (for conflicts=):"*"myapp-bin  (homepage: this repo)"* ]]
}

@test "the AUR is searched by upstream's package name and the repo's name" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" other-name 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  serve_aur '{"results":[]}' other-name myapp
  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -c '.aur_same_app' <<<"$output") == '[]' ]]
  grep -q '^https://aur.archlinux.org/rpc/v5/search/other-name .*by=name' "$GHPKG_TEST_LOG/curl"
  grep -q '^https://aur.archlinux.org/rpc/v5/search/myapp .*by=name' "$GHPKG_TEST_LOG/curl"
}

@test "an AUR package of the same app under another name is found by the search" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  # Like pot-translation for pot-app/pot-desktop: no -bin or -git form of a name.
  echo '{"results":[{"Name":"myapp-translation","Description":"Same app","URL":"https://github.com/me/myapp"}]}' |
    serve https://aur.archlinux.org/rpc/v5/search/myapp
  echo '{"results":[]}' | serve https://aur.archlinux.org/rpc/v5/info
  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -c '[.aur_same_app[].Name]' <<<"$output") == '["myapp-translation"]' ]]
}

@test "upstream's package name, when it belongs to another app, is flagged for provides and conflicts" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  # Like "pot" on the AUR, an unrelated app.
  serve_aur '{"results":[{"Name":"myapp","Description":"Another app","URL":"https://github.com/someone/else"}]}' myapp
  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -c '.foreign_names' <<<"$output") == '[{"name":"myapp","where":"AUR","url":"https://github.com/someone/else"}]' ]]
  [[ $(jq -c '.aur_same_app' <<<"$output") == '[]' ]]
  [[ $(jq -r '.warnings[]' <<<"$output") == *"These names belong to other apps: myapp (AUR, https://github.com/someone/else)"* ]]
}

@test "the runtime-libraries warning names each program that links only to libc, even next to others" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  # A second program that links more than libc, like cardwire's daemon.
  local dir=$BATS_TEST_TMPDIR/build-zst-myapp
  cp "$(command -v jq)" "$dir/usr/bin/myapp-daemon"
  (cd "$dir" && bsdtar --zstd -cf "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" .PKGINFO usr)
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -r '.warnings[]' <<<"$output") == *"These programs link only to the basic C libraries: /usr/bin/myapp. "* ]]
}

@test "dependencies missing from the official repos are flagged, saying whether the AUR has them" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  printf 'core glibc 2.44-1\n' >"$GHPKG_TEST_DB/repo"
  echo '{"results":[{"Name":"gtk3","Description":"On the AUR","URL":"https://example.org"}]}' |
    serve_aur "$(cat)" myapp other-name

  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -c '.unavailable_depends' <<<"$output") == '[{"name":"gtk3","aur":true}]' ]]
  [[ $(jq -r '.warnings[]' <<<"$output") == *"aren't in the official repos: gtk3 (on the AUR only)"* ]]
}

@test "an installed dependency isn't flagged, even when the repos no longer have it" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  printf 'core glibc 2.44-1\n' >"$GHPKG_TEST_DB/repo"
  installed gtk3 3.24-1
  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -c '.unavailable_depends' <<<"$output") == '[]' ]]
}

@test "an AUR package whose homepage is upstream's own website counts as the same app" {
  make_zst "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst" myapp 1.0
  publish me/myapp v1.0 "$BATS_TEST_TMPDIR/myapp-1.0-1-x86_64.pkg.tar.zst"
  # make_zst's .PKGINFO says url = https://example.org/myapp
  echo '{"results":[
    {"Name":"myapp","Description":"Same app, website","URL":"http://www.example.org/myapp/"},
    {"Name":"myapp-git","Description":"Another app","URL":"https://example.org/other"}]}' |
    serve_aur "$(cat)" myapp other-name
  run describe_json_of me/myapp myapp-1.0-1-x86_64.pkg.tar.zst
  [[ $(jq -c '[.aur_same_app[] | [.Name, .matched]]' <<<"$output") == '[["myapp","website"]]' ]]
}
