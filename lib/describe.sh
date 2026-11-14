# shellcheck shell=bash
# describe: download one release file and report what's inside. The package
# is unpacked and read, never run.

# Libraries every program links to. A program that links to nothing else
# usually loads its display, sound or D-Bus libraries at runtime.
BASIC_LIBS=" libc.so.6 libm.so.6 libgcc_s.so.1 ld-linux-x86-64.so.2 libpthread.so.0 libdl.so.2 librt.so.1 libutil.so.1 libstdc++.so.6 "

HICOLOR_INDEX=${HICOLOR_INDEX:-/usr/share/icons/hicolor/index.theme}

# Lines on stdin as a JSON array of strings.
lines_json() { jq -R . | jq -s .; }

# Downloads a file from RELEASE into the cache, unless a good copy is already
# there. Sets FILE_URL, FILE_PATH, FILE_SHA256 and FILE_VERIFIED (true when it
# matched GitHub's checksum).
download_asset() {
  local name=$1 digest dest
  FILE_URL=$(jq -r --arg n "$name" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$RELEASE")
  [[ -n $FILE_URL ]] || die "the latest release has no file named $name"
  digest=$(asset_digest "$FILE_URL")
  dest=$GHPKG_CACHE/sources/$name
  mkdir -p "${dest%/*}"

  if [[ ! -f $dest ]] || [[ -n $digest && $(sha256sum "$dest" | cut -d' ' -f1) != "$digest" ]]; then
    curl -fsSL --connect-timeout 15 --retry 3 -o "$dest.part" "$FILE_URL" ||
      { rm -f "$dest.part"; die "couldn't download $FILE_URL"; }
    mv "$dest.part" "$dest"
  fi

  FILE_PATH=$dest
  FILE_SHA256=$(sha256sum "$dest" | cut -d' ' -f1)
  FILE_VERIFIED=false
  if [[ -n $digest ]]; then
    if [[ $FILE_SHA256 != "$digest" ]]; then
      rm -f "$dest"
      die "$name doesn't match GitHub's checksum, so it was deleted. Try again; if it fails twice, don't use this file."
    fi
    FILE_VERIFIED=true
  fi
}

# Unpacks a .pkg.tar.* or .deb: the package's files into $2/root, metadata
# and scripts into $2/meta. Sets DATA_ARCHIVE to the archive holding the files.
unpack_asset() {
  local file=$1 work=$2 kind=$3 archive
  rm -rf "$work"
  mkdir -p "$work/root" "$work/meta"

  case $kind in
    pkg)
      bsdtar -xf "$file" -C "$work/root" \
        --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL
      bsdtar -xf "$file" -C "$work/meta" .PKGINFO 2>/dev/null || die "$file has no .PKGINFO, so it isn't a pacman package"
      bsdtar -xf "$file" -C "$work/meta" .INSTALL 2>/dev/null || true
      DATA_ARCHIVE=$file
      ;;
    deb)
      bsdtar -xf "$file" -C "$work/meta" || die "$file isn't a readable .deb"
      mkdir -p "$work/meta/control"
      for archive in "$work"/meta/control.tar*; do
        bsdtar -xf "$archive" -C "$work/meta/control"
      done
      for archive in "$work"/meta/data.tar*; do
        bsdtar -xf "$archive" -C "$work/root"
        DATA_ARCHIVE=$archive
      done
      [[ -n ${DATA_ARCHIVE:-} ]] || die "$file has no data.tar inside, so it isn't a usable .deb"
      ;;
  esac
}

# A .PKGINFO as JSON.
pkginfo_json() {
  jq -R -s '
    split("\n") | map(capture("^(?<k>[a-z0-9_]+) = (?<v>.*)$")? )
    | reduce .[] as $e ({}; .[$e.k] += [$e.v])
    | {name: (.pkgname[0] // null), version: (.pkgver[0] // null), description: (.pkgdesc[0] // null),
       url: (.url[0] // null), licenses: (.license // []), depends: (.depend // []),
       optdepends: (.optdepend // []), provides: (.provides // []), conflicts: (.conflict // []),
       replaces: (.replaces // []), backup: (.backup // []), dependency_names: "arch"}' "$1"
}

# A Debian control file as JSON. Dependency names stay in Debian form.
control_json() {
  jq -R -s '
    def list: if . == null then [] else split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) end;
    (capture("(?m)^Description:[ \\t]*(?<d>[^\\n]*)").d // null) as $description
    | gsub("\n[ \t]+"; " ") | split("\n")
    | map(capture("^(?<k>[A-Za-z0-9-]+):[ \\t]*(?<v>.*)$")? | {(.k | ascii_downcase): .v})
    | add // {}
    | {name: .package, version: .version, description: $description, url: .homepage,
       licenses: [], depends: ((."pre-depends" | list) + (.depends | list)),
       optdepends: ((.recommends | list) + (.suggests | list)),
       provides: (.provides | list), conflicts: ((.conflicts | list) + (.breaks | list)),
       replaces: (.replaces | list), backup: [], dependency_names: "debian"}' "$1"
}

# Scripts that pacman or dpkg would run as root, as a JSON array of {name, text}.
scripts_json() {
  local work=$1 kind=$2 script found=()
  if [[ $kind == pkg ]]; then
    [[ -f $work/meta/.INSTALL ]] && found+=("$work/meta/.INSTALL")
  else
    for script in preinst postinst prerm postrm config triggers; do
      [[ -f $work/meta/control/$script ]] && found+=("$work/meta/control/$script")
    done
  fi
  for script in "${found[@]}"; do
    jq -n --arg name "${script##*/}" --rawfile text "$script" '{name: $name, text: $text}'
  done | jq -s .
}

# Files inside the package that those scripts call, with their text.
called_scripts_json() {
  local work=$1 path
  jq -r '.[].text' <<<"$2" | grep -oE '(/usr|/opt|/etc|/lib)/[A-Za-z0-9_./+@-]+' | sort -u |
    while IFS= read -r path; do
      [[ -f $work/root$path && ! -L $work/root$path ]] || continue
      (( $(stat -c %s "$work/root$path") <= 65536 )) || continue
      jq -n --arg path "$path" --rawfile text "$work/root$path" '{path: $path, text: $text}'
    done | jq -s .
}

# What each ELF file links to, and who provides it. Prints a JSON object.
libraries_json() {
  local root=$1 file lib dir owner needed binaries=() bundled all_needed=()
  bundled=" $(find "$root" -name '*.so*' -printf '%f ') "

  while IFS= read -r file; do
    [[ -f $root/$file && ! -L $root/$file ]] || continue
    [[ $(head -c4 "$root/$file" 2>/dev/null | tr -d '\0') == $'\x7fELF' ]] || continue
    needed=$(readelf -d --wide "$root/$file" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
    binaries+=("$(jq -n --arg path "/$file" --argjson needed "$(lines_json <<<"$needed" | jq 'map(select(length > 0))')" \
      '{path: $path, needed: $needed}')")
    [[ -n $needed ]] && mapfile -t -O "${#all_needed[@]}" all_needed <<<"$needed"
  done < <(cd "$root" && find . -type f -printf '%P\n' | sort)

  {
    for lib in $(printf '%s\n' "${all_needed[@]}" | sort -u); do
      owner=
      if [[ $bundled == *" $lib "* ]]; then
        jq -n --arg lib "$lib" '{lib: $lib, bundled: true, owner: null, basic: false}'
        continue
      fi
      for dir in /usr/lib /usr/lib64 /lib /lib64; do
        if [[ -e $dir/$lib ]]; then
          owner=$(pacman -Qoq "$dir/$lib" 2>/dev/null | head -1) || owner=
          break
        fi
      done
      jq -n --arg lib "$lib" --arg owner "$owner" --argjson basic "$([[ $BASIC_LIBS == *" $lib "* ]] && echo true || echo false)" \
        '{lib: $lib, bundled: false, owner: (if $owner == "" then null else $owner end), basic: $basic}'
    done
  } | jq -s --argjson binaries "$(printf '%s\n' "${binaries[@]}" | jq -s 'map(select(. != null))')" \
    '{binaries: $binaries, needed: ., unresolved: [.[] | select(.bundled | not) | select(.owner == null) | .lib]}'
}

# Icon folders the system's hicolor theme doesn't know, such as "256x256/app".
odd_icon_dirs() {
  [[ -f $HICOLOR_INDEX ]] || return 0
  local known
  known=" $(sed -n 's/^Directories=//p' "$HICOLOR_INDEX" | tr ',' ' ') $(sed -n 's/^ScaledDirectories=//p' "$HICOLOR_INDEX" | tr ',' ' ') "
  grep -E '^usr/share/icons/hicolor/' | sed -E 's#^usr/share/icons/hicolor/##; s#/[^/]+$##' | sort -u |
    while IFS= read -r dir; do
      [[ $known == *" $dir "* ]] || echo "$dir"
    done
}

describe_json() {
  local repo=$1 name=$2 kind work files meta scripts setuid warnings=() libs
  fetch_release "$repo" || die "$repo: $GH_ERROR"
  read -r _ kind <<<"$(asset_kind "$name")" || true
  [[ $kind == pkg || $kind == deb ]] ||
    die "$name isn't a .pkg.tar.zst or .deb. ghpkg can describe those two kinds only."

  download_asset "$name"
  work=$GHPKG_CACHE/describe/$name
  unpack_asset "$FILE_PATH" "$work" "$kind"

  if [[ $kind == pkg ]]; then
    meta=$(pkginfo_json "$work/meta/.PKGINFO")
  else
    meta=$(control_json "$work/meta/control/control")
  fi
  scripts=$(scripts_json "$work" "$kind")
  files=$(cd "$work/root" && find . \( -type f -o -type l \) -printf '%P\n' | sort)
  setuid=$(bsdtar -tvf "$DATA_ARCHIVE" | grep -E '^-..[sS]|^-.....[sS]' | sed -E 's/^([^ ]+ +){8}//; s#^\./##' || true)
  libs=$(libraries_json "$work/root")

  # Things that need a person's decision.
  $FILE_VERIFIED || warnings+=("GitHub lists no checksum for $name, so the download can't be verified. Its sha256 is $FILE_SHA256.")
  [[ $kind == deb ]] && warnings+=("Dependencies are Debian package names. Each needs translating to its Arch name.")
  [[ $(jq length <<<"$scripts") -gt 0 ]] && warnings+=("Has scripts that run as root when installing or removing: $(jq -r 'map(.name) | join(", ")' <<<"$scripts"). Read them before carrying them over.")
  if [[ $(jq '[.binaries[] | select(.needed | length > 0)] | length' <<<"$libs") -gt 0 ]] &&
    [[ $(jq '[.needed[] | select((.bundled | not) and (.basic | not))] | length' <<<"$libs") -eq 0 ]]; then
    warnings+=("The programs link only to the basic C libraries. Programs like this usually load display, GL, sound or D-Bus libraries at runtime, so the dependency list may be incomplete: compare it with the AUR's PKGBUILD or upstream's docs.")
  fi
  [[ $(jq '.unresolved | length' <<<"$libs") -gt 0 ]] && warnings+=("Libraries not on this system: $(jq -r '.unresolved | join(", ")' <<<"$libs"). Find their Arch packages with 'pacman -F <library>'.")
  if grep -q '^opt/' <<<"$files" && ! grep -qE '^usr/bin/' <<<"$files"; then
    warnings+=("Programs are in /opt, with nothing in /usr/bin. The PKGBUILD should link the main program into /usr/bin.")
  fi
  local odd
  odd=$(odd_icon_dirs <<<"$files")
  [[ -n $odd ]] && warnings+=("Icon folders the hicolor theme doesn't know, so icons there won't show: $(paste -sd' ' <<<"$odd").")
  [[ -n $setuid ]] && warnings+=("Files with the setuid bit (they run as their owner, usually root): $(paste -sd' ' <<<"$setuid").")
  if [[ $kind == deb ]]; then
    grep -q '^etc/apt/' <<<"$files" && warnings+=("Adds an apt repository under /etc/apt. Delete it in package().")
    grep -qE '^usr/share/(lintian|menu)/' <<<"$files" && warnings+=("Has Debian-only files in /usr/share/lintian or /usr/share/menu. Delete them in package().")
    grep -q '^usr/share/doc/' <<<"$files" && warnings+=("Has /usr/share/doc (Debian changelogs and copyright). Keeping it is optional.")
  fi
  grep -qvE '^(usr|opt)/' <<<"$files" && warnings+=("Has files outside /usr and /opt: $(grep -vE '^(usr|opt)/' <<<"$files" | head -5 | paste -sd' ').")

  jq -n \
    --arg repo "$repo" --arg tag "$(jq -r .tag_name <<<"$RELEASE")" \
    --arg name "$name" --arg kind "$kind" --arg url "$FILE_URL" --arg path "$FILE_PATH" \
    --arg sha256 "$FILE_SHA256" --argjson verified "$FILE_VERIFIED" \
    --argjson meta "$meta" --argjson scripts "$scripts" \
    --argjson called "$(called_scripts_json "$work" "$scripts")" \
    --argjson files "$(lines_json <<<"$files" | jq 'map(select(length > 0))')" \
    --argjson setuid "$(lines_json <<<"$setuid" | jq 'map(select(length > 0))')" \
    --argjson libs "$libs" \
    --argjson warnings "$(printf '%s\n' "${warnings[@]}" | lines_json | jq 'map(select(length > 0))')" \
    '{repo: $repo, tag: $tag,
      file: {name: $name, kind: $kind, url: $url, path: $path, sha256: $sha256, verified: $verified},
      metadata: $meta, scripts: $scripts, called_scripts: $called,
      files: {count: ($files | length),
              programs: [$files[] | select(test("^(usr/(local/)?s?bin|s?bin)/"))],
              desktop: [$files[] | select(test("^usr/share/applications/.*\\.desktop$"))],
              systemd: [$files[] | select(test("(^|/)systemd/(system|user)/[^/]+$"))],
              icons: [$files[] | select(test("^usr/share/(icons|pixmaps)/"))],
              opt: [$files[] | select(startswith("opt/"))],
              outside_usr: [$files[] | select(test("^(usr|opt)/") | not)],
              setuid: $setuid,
              all: $files},
      libraries: $libs, warnings: $warnings}'
}

describe() {
  local json=false args=() result
  while (( $# )); do
    case $1 in
      --json) json=true ;;
      -*) die "unknown option $1" ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  (( ${#args[@]} == 2 )) || die "usage: ghpkg describe <owner/repo or GitHub URL> <release file> [--json]"
  local repo
  repo=$(parse_repo "${args[0]}") || die "'${args[0]}' isn't owner/repo or a GitHub URL"

  result=$(describe_json "$repo" "${args[1]}") || return 1
  if $json; then
    echo "$result"
  else
    print_description <<<"$result"
  fi
}

# The human-readable form of describe_json's output.
print_description() {
  jq -r '
    def few($n): if length > $n then .[:$n] + ["… and \(length - $n) more"] else . end;
    def section($title; $items): if ($items | length) == 0 then empty
      else "", "\($title):", ($items | few(12) | .[] | "  \(.)") end;
    .metadata as $m |
    "\(.file.name) from \(.repo) \(.tag)",
    "  Downloaded to \(.file.path)",
    "  sha256 \(.file.sha256) " + (if .file.verified then "(matches GitHub'"'"'s checksum)" else "(GitHub lists no checksum)" end),
    "",
    "Upstream package: \($m.name // "?") \($m.version // "?")",
    (if $m.description then "  \($m.description)" else empty end),
    (if $m.url then "  \($m.url)" else empty end),
    (if ($m.licenses | length) > 0 then "  Licence: \($m.licenses | join(", "))" else empty end),
    section("Dependencies" + (if $m.dependency_names == "debian" then " (Debian names)" else "" end); $m.depends),
    section("Optional dependencies"; $m.optdepends),
    section("Provides"; $m.provides),
    section("Conflicts"; $m.conflicts),
    section("Backup files"; $m.backup),
    (if (.scripts | length) == 0 then "", "Scripts that run as root: none"
     else "", "Scripts that run as root:",
       (.scripts[] | "", "  --- \(.name) ---", (.text | rtrimstr("\n") | split("\n")[] | "  \(.)")),
       (.called_scripts[] | "", "  --- \(.path) (called by the above) ---", (.text | rtrimstr("\n") | split("\n")[] | "  \(.)"))
     end),
    "",
    "Files: \(.files.count)",
    section("Programs"; .files.programs),
    section("Launcher entries"; .files.desktop),
    section("systemd units"; .files.systemd),
    section("Icons"; .files.icons),
    section("Files outside /usr"; .files.outside_usr),
    "",
    "Linked libraries:",
    (if (.libraries.needed | length) == 0 then "  none (no programs, or only scripts)"
     else (.libraries.needed[] | "  \(.lib)  " +
       (if .bundled then "bundled in the package" elif .owner then "from \(.owner)" else "NOT ON THIS SYSTEM" end))
     end),
    (if (.warnings | length) == 0 then "", "Nothing needs a decision."
     else "", "Needs a decision:", (.warnings[] | "  - \(.)") end)
  '
}
