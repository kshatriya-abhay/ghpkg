# shellcheck shell=bash
# inspect: what a GitHub release offers, and which package names are free.
# Only reads; changes nothing.

AUR_RPC=${AUR_RPC:-https://aur.archlinux.org/rpc/v5/info}
AUR_SEARCH=${AUR_SEARCH:-https://aur.archlinux.org/rpc/v5/search}

# owner/repo, from "owner/repo" or any github.com URL into the repo.
parse_repo() {
  local arg=$1 owner name
  arg=${arg#https://}
  arg=${arg#http://}
  arg=${arg#www.}
  arg=${arg#github.com/}
  IFS=/ read -r owner name _ <<<"$arg"
  name=${name%.git}
  [[ $owner =~ ^[A-Za-z0-9_.-]+$ && $name =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  echo "$owner/$name"
}

# How a release file can be packaged, as "rank kind" (1 is best), or nothing
# when it isn't a Linux x86_64 file ghpkg can use.
asset_kind() {
  local name=${1,,}
  case $name in
    *.sig | *.asc | *.sha256 | *.sha512 | *.md5 | *.zsync | *.sym | *sha256sums* | *.txt | *.json | *.md) return ;;
    *-aur.tar.gz | *-debug-*) return ;;
  esac
  [[ $name =~ (macos|darwin|osx|windows|win64|win32|freebsd|openbsd|netbsd|android|[-_.]ios[-_.]) ]] && return
  [[ $name =~ (aarch64|arm64|armv[67]|armhf|armel|riscv|i[36]86|ppc64|s390x|mips|loong) ]] && return
  case $name in
    *.pkg.tar.zst | *.pkg.tar.xz) echo "1 pkg" ;;
    *.deb) echo "2 deb" ;;
    *.tar.gz | *.tgz | *.tar.xz | *.tar.zst | *.tar.bz2) echo "3 tarball" ;;
    *.appimage) echo "4 appimage" ;;
    *.rpm) echo "5 rpm" ;;
  esac
}

# The release's usable files as a JSON array, best first.
release_files_json() {
  local name kind rank
  while IFS= read -r name; do
    read -r rank kind <<<"$(asset_kind "$name")"
    [[ -n ${kind:-} ]] || continue
    jq -c --arg name "$name" --arg kind "$kind" --argjson rank "$rank" \
      '.assets[] | select(.name == $name)
       | {name, kind: $kind, rank: $rank, size, url: .browser_download_url,
          sha256: (if (.digest // "") | startswith("sha256:") then .digest[7:] else null end)}' <<<"$RELEASE"
    kind=
  done < <(jq -r '.assets[].name' <<<"$RELEASE") | jq -s 'sort_by(.rank, .name)'
}

# Which of the given names exist on the AUR, as a JSON object of name -> true
# or false. null when the AUR can't be reached.
aur_names_json() {
  local query=() name result
  for name; do query+=(--data-urlencode "arg[]=$name"); done
  if result=$(curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 -G "${query[@]}" "$AUR_RPC" 2>/dev/null); then
    jq -c --args '[.results[].Name] as $taken | [$ARGS.positional[] | {(.): (. as $n | $taken | index($n) != null)}] | add' \
      "$@" <<<"$result"
  else
    echo null
  fi
}

# The AUR packages among the given names, as a JSON array of their details
# (Name, Description, URL). null when the AUR can't be reached.
aur_info_json() {
  local query=() name result
  (( $# )) || { echo '[]'; return; }
  for name; do query+=(--data-urlencode "arg[]=$name"); done
  if result=$(curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 -G "${query[@]}" "$AUR_RPC" 2>/dev/null); then
    jq -c '[.results[] | {Name, Description, URL}]' <<<"$result"
  else
    echo null
  fi
}

# AUR packages whose names contain any of the given names, as one JSON array
# of {Name, Description, URL}, or null when the AUR can't be reached. Names
# shorter than two letters are skipped: the AUR won't search for them.
aur_search_json() {
  local name result all='[]'
  for name; do
    (( ${#name} >= 2 )) || continue
    result=$(curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 -G --data-urlencode by=name \
      "$AUR_SEARCH/$(jq -rn --arg n "$name" '$n | @uri')" 2>/dev/null) || { echo null; return; }
    all=$(jq -c --argjson all "$all" '$all + [.results[] | {Name, Description, URL}] | unique_by(.Name)' <<<"$result")
  done
  echo "$all"
}

# The AUR packages that are this same app: those whose names contain one of
# the given names or the repo's name, and whose homepage is github.com/<repo>,
# or upstream's own website when one is given. The name search finds packages
# such as pot-translation for pot-app/pot-desktop, which no -bin or -git form
# of a name would. A JSON array of {Name, URL, matched} (matched is "repo" or
# "website"), or null when the AUR can't be reached. A package that only
# shares a name is never included: listing it in conflicts= would make pacman
# uninstall another app.
aur_same_app_json() {
  local repo=$1 website=${2:-} found names
  shift 2
  mapfile -t names < <(printf '%s\n' "$@" "$(tr '[:upper:]' '[:lower:]' <<<"${repo#*/}")" | grep -v '^$' | awk '!seen[$0]++')
  found=$(aur_search_json "${names[@]}")
  if [[ $found == null ]]; then
    echo null
    return
  fi
  same_app_of "$repo" "$website" <<<"$found"
}

# Names among the given ones that belong to another app: a package in the
# official repos, or on the AUR, whose homepage is neither github.com/<repo>
# nor upstream's website. Such a name must stay out of provides= and
# conflicts=. A JSON array of {name, where, url}.
foreign_names_json() {
  local repo=$1 website=${2:-} name info url aur found=()
  shift 2
  for name; do
    info=$(pacman -Si "$name" 2>/dev/null) || continue
    url=$(sed -n 's/^URL *: //p' <<<"$info" | head -1)
    if [[ $(jq -n --arg u "$url" '[{Name: "x", URL: $u}]' | same_app_of "$repo" "$website") == '[]' ]]; then
      found+=("$(jq -c -n --arg n "$name" --arg u "$url" '{name: $n, where: "official repos", url: (if $u == "" then null else $u end)}')")
    fi
  done
  aur=$(aur_info_json "$@")
  if [[ $aur != null ]]; then
    while IFS= read -r name; do
      [[ -n $name ]] && found+=("$name")
    done < <(jq -c --argjson same "$(same_app_of "$repo" "$website" <<<"$aur")" \
      '.[] | select(.Name as $n | ($ARGS.positional | index($n)) and ($same | map(.Name) | index($n) | not))
       | {name: .Name, where: "AUR", url: .URL}' --args "$@" <<<"$aur")
  fi
  printf '%s\n' "${found[@]}" | jq -c -s 'map(select(. != null)) | unique_by(.name)'
}

# Filters aur_info_json's output on stdin down to the same app, as above.
same_app_of() {
  jq -c --arg repo "https://github.com/$1" --arg site "${2:-}" '
    def norm: ascii_downcase | sub("^https?://(www\\.)?"; "") | rtrimstr("/") | rtrimstr(".git");
    [.[] | ((.URL // "") | norm) as $u
     | if $u == ($repo | norm) then {Name, URL, matched: "repo"}
       elif $site != "" and $u == ($site | norm) then {Name, URL, matched: "website"}
       else empty end]'
}

# The official repos' package of that name, as JSON, or null.
official_json() {
  local info
  info=$(pacman -Si "$1" 2>/dev/null) || { echo null; return; }
  jq -n --arg name "$1" \
    --arg repo "$(awk -F' : ' '/^Repository/{print $2; exit}' <<<"$info")" \
    --arg version "$(awk -F' : ' '/^Version/{print $2; exit}' <<<"$info")" \
    '{name: $name, repository: $repo, version: $version}'
}

# Package folders whose PKGBUILD points at this repo.
local_pkgs_for() {
  local pkg
  for pkg in $(all_pkgs); do
    [[ $(pkgvar "$pkg" _ghrepo) == "$1" ]] && echo "$pkg"
  done
  return 0
}

# Those of the repo's package folders whose package isn't installed, such as
# one removed with pacman: `ghpkg update <package>` installs it again.
local_uninstalled_for() {
  local pkg
  for pkg in $(local_pkgs_for "$1"); do
    pacman -Q "$pkg" &>/dev/null || echo "$pkg"
  done
  return 0
}

inspect_json() {
  local repo=$1 info name tag version installed
  gh_get "$GITHUB_API/repos/$repo" || die "$repo: $GH_ERROR"
  info=$GH_BODY
  fetch_release "$repo" || die "$repo has no usable release: $GH_ERROR"

  name=$(jq -r '.name | ascii_downcase' <<<"$info")
  tag=$(jq -r .tag_name <<<"$RELEASE")
  version=$(tag_to_pkgver "$tag") || version=
  # A package with the suggested name may be installed without a PKGBUILD here.
  installed=$(pacman -Q "$name-gh" 2>/dev/null | awk '{print $2}') || installed=

  jq -n \
    --arg repo "$repo" \
    --argjson info "$info" \
    --argjson release "$RELEASE" \
    --arg version "$version" \
    --argjson files "$(release_files_json)" \
    --argjson official "$(official_json "$name")" \
    --argjson aur "$(aur_names_json "$name" "$name-bin" "$name-git" "$name-gh")" \
    --argjson local "$(local_pkgs_for "$repo" | jq -R . | jq -s .)" \
    --argjson uninstalled "$(local_uninstalled_for "$repo" | jq -R . | jq -s .)" \
    --arg suggested "$name-gh" --arg installed "$installed" \
    '{repo: $repo, name: ($info.name | ascii_downcase), description: $info.description,
      license: $info.license.spdx_id,
      release: {tag: $release.tag_name, version: (if $version == "" then null else $version end),
                published: $release.published_at, prerelease: $release.prerelease,
                tag_in_source: (if $version == "" then null
                                elif $release.tag_name == $version then "$pkgver"
                                elif $release.tag_name == "v" + $version then "v$pkgver"
                                else null end)},
      files: $files, official: $official, aur: $aur, local: $local,
      local_uninstalled: $uninstalled,
      suggested_name: $suggested,
      suggested_installed: (if $installed == "" then null else $installed end)}'
}

inspect() {
  local json=false arg='' result
  while (( $# )); do
    case $1 in
      --json) json=true ;;
      -*) die "unknown option $1" ;;
      *) arg=$1 ;;
    esac
    shift
  done
  [[ -n $arg ]] || die "usage: ghpkg inspect <owner/repo or GitHub URL> [--json]"
  local repo
  repo=$(parse_repo "$arg") || die "'$arg' isn't owner/repo or a GitHub URL"

  result=$(inspect_json "$repo") || return 1
  if $json; then
    echo "$result"
  else
    print_inspection <<<"$result"
  fi
}

# The human-readable form of inspect_json's output.
print_inspection() {
  jq -r '
    def size: if . == null then "" elif . >= 1048576 then "\(. / 1048576 | . * 10 | round / 10) MB"
              else "\(. / 1024 | round) KB" end;
    def kindname: {pkg: "Arch package", deb: ".deb", tarball: "archive", appimage: "AppImage", rpm: ".rpm"}[.];
    "\(.repo): \(.description // "no description")\(if .license and .license != "NOASSERTION" then " (\(.license))" else "" end)",
    "Latest release: \(.release.tag) (\(.release.published[:10]))"
      + (if .release.version then ", version \(.release.version)" else ", which isn'"'"'t usable as a pacman version" end),
    "",
    (if (.files | length) == 0 then "No Linux x86_64 files ghpkg can use in this release."
     else "Linux x86_64 files, best first:",
       (.files | to_entries[] | "  \(.key + 1). \(.value.name)  [\(.value.kind | kindname), \(.value.size | size), "
          + (if .value.sha256 then "checksum on GitHub" else "no checksum on GitHub" end) + "]")
     end),
    "",
    (if .official then "Official repos: \(.official.repository)/\(.official.name) \(.official.version). Install that instead."
     else "Official repos: nothing named \(.name)." end),
    (if .aur == null then "AUR: couldn'"'"'t be reached."
     else "AUR: " + ([.aur | to_entries[] | "\(.key) \(if .value then "taken" else "free" end)"] | join(", ")) end),
    (if (.local | length) > 0 then "Already set up as: \(.local | join(", "))."
     else "Not set up in your packages yet." end),
    (.local_uninstalled[]? | "\(.)'"'"'s PKGBUILD is here, but it isn'"'"'t installed. To install it: ghpkg update \(.)"),
    (if .suggested_installed and (.suggested_name as $n | .local | index($n) | not)
     then "But \(.suggested_name) \(.suggested_installed) is installed: from another packages folder, or by hand. Check before using that name."
     else empty end),
    (if .release.tag_in_source then "Download links use the tag \(.release.tag): write it in source= as \(.release.tag_in_source)."
     else empty end),
    "",
    (if .official then empty
     elif .aur != null and .aur[.suggested_name] then "Suggested name \(.suggested_name) is taken on the AUR: pick another."
     else "Suggested name: \(.suggested_name)" end),
    (if (.files | length) > 0 then "Next: ghpkg describe \(.repo) \(.files[0].name)" else empty end)
  '
}
