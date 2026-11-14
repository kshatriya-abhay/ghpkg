# shellcheck shell=bash
# add: package an app whose latest release has a .pkg.tar.zst, asking the
# user at each step: which file, the name, the dependencies, and any script
# that runs as root. Built from inspect, describe and test-build.

# Packages of the basic libraries. Linked-library owners in this list are
# suggested only when upstream lists them too, as Arch packages do.
BASIC_PKGS=" glibc gcc-libs libgcc libstdc++ "

# Asks for text, with a default used on Enter.
ask() {
  local answer
  read -r -p "$1 [$2] " answer
  echo "${answer:-$2}"
}

# Asks until one of the given single-letter answers is typed. No default.
ask_letter() {
  local question=$1 letters=$2 answer
  while true; do
    read -r -p "$question " answer
    answer=${answer,,}
    [[ ${#answer} -eq 1 && $letters == *"$answer"* ]] && { echo "$answer"; return; }
  done
}

# Lets the user pick one of several lines; prints the chosen one.
choose() {
  local question=$1 items=() i answer
  mapfile -t items
  for i in "${!items[@]}"; do echo "  $((i + 1)). ${items[i]}" >&2; done
  while true; do
    answer=$(ask "$question" 1)
    [[ $answer =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#items[@]} )) &&
      { echo "${items[answer - 1]}"; return; }
  done
}

# Lines on stdin, opened in the user's editor; prints what's left, minus
# comments and blank lines.
edit_lines() {
  local file
  file=$(mktemp "${TMPDIR:-/tmp}/ghpkg-XXXXXX.txt")
  cat >"$file"
  "${VISUAL:-${EDITOR:-nano}}" "$file" </dev/tty >/dev/tty
  grep -vE '^\s*(#|$)' "$file" | sed 's/^\s*//; s/\s*$//' || true
  rm -f "$file"
}

# Lines on stdin as the inside of a bash array, single-quoted: on one line
# when short, one item per line when long.
bash_array() {
  local items=() item quoted=() joined
  mapfile -t items
  for item in "${items[@]}"; do
    [[ -n $item ]] && quoted+=("'${item//\'/\'\\\'\'}'")
  done
  (( ${#quoted[@]} )) || return 0
  joined=${quoted[*]}
  if (( ${#joined} <= 60 )); then
    printf '%s' "$joined"
  else
    printf '\n'
    printf '  %s\n' "${quoted[@]}"
  fi
}

# array_value VAR: bash_array of stdin, into VAR. Set without a subshell so the
# long form keeps its last newline and the closing ")" gets a line of its own.
array_value() {
  local -n _out=$1
  _out=$(bash_array)
  [[ $_out == $'\n'* ]] && _out+=$'\n'
  return 0
}

# Text for inside double quotes in a PKGBUILD.
dquote_escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//\$/\\\$}
  text=${text//\`/\\\`}
  printf '%s' "$text"
}

# A package name without a version constraint: "foo>=1.0" gives "foo".
bare_name() { sed -E 's/[<>=].*$//'; }

# Fills a template's @KEY@ placeholders. Arguments are KEY=value.
render_template() {
  local text pair key value
  text=$(<"$1")
  shift
  for pair; do
    key=${pair%%=*}
    value=${pair#*=}
    text=${text//"@$key@"/"$value"}
  done
  printf '%s\n' "$text"
}

# The name to suggest: upstream's package name without -git or -bin, or the
# repo's name when upstream's is reverse-DNS (ai.example.app), plus -gh.
suggest_name() {
  local upstream=$1 repo_name=$2 base
  base=${upstream%-git}
  base=${base%-bin}
  [[ -z $base || $base == *.* ]] && base=$repo_name
  echo "${base,,}-gh"
}

valid_pkgname() { [[ $1 =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; }

add() {
  local arg='' file='' name=''
  while (( $# )); do
    case $1 in
      --file) file=${2:?--file needs a release file name}; shift ;;
      --name) name=${2:?--name needs a package name}; shift ;;
      -*) die "unknown option $1" ;;
      *) arg=$1 ;;
    esac
    shift
  done
  [[ -n $arg ]] || die "usage: ghpkg add <owner/repo or GitHub URL> [--file <release file>] [--name <package>]"
  [[ -t 0 ]] || die "ghpkg add asks questions, so it needs a terminal. Coding agents: use the ghpkg skill instead ($(ghpkg_skill_path))."

  local repo info desc version tag pkg_files
  repo=$(parse_repo "$arg") || die "'$arg' isn't owner/repo or a GitHub URL"

  # 1. The release ----------------------------------------------------------
  heading "1/7 What $repo's latest release offers"
  info=$(inspect_json "$repo") || return 1
  print_inspection <<<"$info" | grep -v '^Next: '

  if [[ $(jq -r '.official != null' <<<"$info") == true ]]; then
    confirm "The official repos have it. Package it from GitHub anyway?" n || return 0
  fi
  if [[ $(jq '.local | length' <<<"$info") -gt 0 ]]; then
    confirm "You already have a PKGBUILD for $repo. Add another one?" n || return 0
  fi

  version=$(jq -r '.release.version // empty' <<<"$info")
  tag=$(jq -r '.release.tag' <<<"$info")
  [[ -n $version ]] || die "the latest release is tagged '$tag', which isn't usable as a pacman version, so ghpkg can't track it"

  pkg_files=$(jq -r '.files[] | select(.kind == "pkg") | .name' <<<"$info")
  if [[ -z $pkg_files ]]; then
    if jq -e '.files[] | select(.kind == "deb")' <<<"$info" >/dev/null; then
      die "this release has no .pkg.tar.zst, only a .deb. Packaging a .deb takes judgement: use a coding agent with the ghpkg skill (ghpkg skill install)."
    fi
    die "this release has no .pkg.tar.zst for Linux x86_64, so ghpkg add can't package it"
  fi
  if [[ -n $file ]]; then
    grep -qxF "$file" <<<"$pkg_files" || die "$file isn't one of this release's .pkg.tar.zst files"
  elif [[ $(wc -l <<<"$pkg_files") -eq 1 ]]; then
    file=$pkg_files
  else
    echo
    file=$(choose "Which file?" <<<"$pkg_files")
  fi
  [[ $file =~ ^[A-Za-z0-9._+-]+$ ]] || die "the file name '$file' has characters a PKGBUILD can't use safely"

  # 2. Inside the file ------------------------------------------------------
  heading "2/7 What's inside $file"
  desc=$(describe_json "$repo" "$file") || return 1
  print_description <<<"$desc"

  # 3. Name -----------------------------------------------------------------
  heading "3/7 Package name, and the packages it replaces"
  local default taken answer
  default=$(suggest_name "$(jq -r '.metadata.name // empty' <<<"$desc")" "${repo#*/}")
  [[ -n $name ]] && default=$name
  while true; do
    name=$(ask "Package name" "$default")
    if ! valid_pkgname "$name"; then
      echo "  Package names use lowercase letters, digits and @ . _ + -, and can't start with - or a dot."
    elif has_pkg "$name"; then
      echo "  $GHPKG_ROOT/$name already exists."
    else
      taken=$(aur_names_json "$name")
      if [[ $taken == null ]]; then
        warn "couldn't reach the AUR to check that $name is free there"
        confirm "  Use $name anyway?" n && break
      elif [[ $(jq -r --arg n "$name" '.[$n]' <<<"$taken") == true ]]; then
        echo "  $name is taken on the AUR. AUR helpers would replace your package with that one, so pick another."
      else
        break
      fi
    fi
    default=$name
  done

  # The same app may already be on the AUR under other names. Installing this
  # package should replace those, but never an unrelated package that only
  # shares a name, so the user confirms each one.
  local same_app='' aur_candidates up_base repo_name
  up_base=$(jq -r '.metadata.name // empty' <<<"$desc")
  repo_name=$(tr '[:upper:]' '[:lower:]' <<<"${repo#*/}")
  aur_candidates=$(for n in "${name%-gh}" "$up_base" "$repo_name"; do
    [[ -n $n ]] && printf '%s\n' "$n" "$n-bin" "$n-git"; done | grep -vxF "$name" | awk '!seen[$0]++')
  local aur
  # shellcheck disable=SC2086 # one name per word
  aur=$(aur_info_json $aur_candidates)
  if [[ $aur == null ]]; then
    warn "couldn't reach the AUR, so there's no check for the same app under other names there"
  elif [[ $(jq length <<<"$aur") -gt 0 ]]; then
    echo
    echo "The AUR has packages with related names. List the ones that are this same app in"
    echo "conflicts=, so installing yours replaces them. Never an unrelated app that only shares"
    echo "a name: pacman would uninstall it."
    local matches
    matches=$(same_app_of "$repo" "$(jq -r '.metadata.url // empty' <<<"$desc")" <<<"$aur")
    jq -r --argjson m "$matches" '.[] | .Name as $n | ($m | map(select(.Name == $n))[0].matched) as $why
      | "  \(.Name)  \(if $why == "repo" then "[same GitHub repo] " elif $why == "website" then "[same website] " else "" end)\(.Description // "")"' <<<"$aur"
    same_app=$(jq -r '.[].Name' <<<"$matches")
    echo
    if [[ -n $same_app ]]; then
      echo "Proposed: $(paste -sd' ' <<<"$same_app") (their homepage is this repo or upstream's website)."
    else
      echo "Proposed: none (no homepage there is this repo or upstream's website)."
    fi
    answer=$(ask_letter "Use that? [y]es, [n]one, [e]dit:" yne)
    case $answer in
      n) same_app= ;;
      e) same_app=$({ echo "# One AUR package per line that is this same app."; echo "$same_app"; } | edit_lines) ;;
    esac
  fi

  # 4. Dependencies ---------------------------------------------------------
  heading "4/7 Dependencies"
  local upstream_deps linked proposed missing dep why line depends optdepends
  upstream_deps=$(jq -r '.metadata.depends[]' <<<"$desc")
  linked=$(jq -r '.libraries.needed[] | select(.owner != null) | .owner' <<<"$desc" | sort -u)
  proposed=$upstream_deps
  while IFS= read -r dep; do
    [[ -n $dep ]] || continue
    grep -qx "$dep" <(bare_name <<<"$upstream_deps") && continue
    [[ $BASIC_PKGS == *" $dep "* ]] && continue
    proposed+=$'\n'$dep
  done <<<"$linked"
  proposed=$(grep -v '^$' <<<"$proposed" || true)
  missing=$(xargs -r pacman -T <<<"$proposed" 2>/dev/null || true)

  echo "Proposed (nothing is added until you confirm):"
  while IFS= read -r dep; do
    [[ -n $dep ]] || continue
    local why=()
    grep -qxF "$dep" <<<"$upstream_deps" && why+=("upstream's list")
    grep -qx "$(bare_name <<<"$dep")" <<<"$linked" && why+=("a linked library")
    line="  $dep  ($(IFS=,; echo "${why[*]}" | sed 's/,/, /g'))"
    grep -qxF "$dep" <<<"$missing" && line+="  not installed: installing would pull it in"
    echo "$line"
  done <<<"$proposed"
  [[ -n $proposed ]] || echo "  (none)"
  if jq -e '.warnings[] | select(contains("basic C libraries"))' <<<"$desc" >/dev/null; then
    echo
    echo "  Note: the programs link only to the basic C libraries, so they probably load"
    echo "  more at runtime (display, GL, sound, D-Bus) that no list here can show."
    echo "  Compare with the AUR's PKGBUILD or upstream's docs, and add them with 'e'."
  fi
  echo
  answer=$(ask_letter "Use these? [y]es, [u]pstream's list only, [e]dit:" yue)
  case $answer in
    y) depends=$proposed ;;
    u) depends=$upstream_deps ;;
    e) depends=$({ echo "# One dependency per line. Delete a line to drop it; add lines for more."; echo "$proposed"; } | edit_lines) ;;
  esac

  optdepends=$(jq -r '.metadata.optdepends[]' <<<"$desc")
  if [[ -n $optdepends ]]; then
    echo
    echo "Optional dependencies from upstream:"
    sed 's/^/  /' <<<"$optdepends"
    answer=$(ask_letter "Keep them? [y]es, [n]one, [e]dit:" yne)
    case $answer in
      n) optdepends= ;;
      e) optdepends=$({ echo "# One per line, as 'package: what it's for'."; echo "$optdepends"; } | edit_lines) ;;
    esac
  fi

  # 5. Scripts that run as root -----------------------------------------------
  heading "5/7 Scripts that run as root"
  local install_file=''
  if [[ $(jq '.scripts | length' <<<"$desc") -eq 0 ]]; then
    echo "None: upstream's package runs nothing as root."
  else
    echo "Upstream's package runs its .INSTALL as root when installing, updating and removing."
    echo "It's shown in full under step 2, with the scripts it calls."
    echo "The repack leaves upstream's .INSTALL out, so it only runs if you carry it over."
    answer=$(ask_letter "Carry it over as $name.install? [y]es, [n]o (leave it out), [s]top:" yns)
    case $answer in
      y) install_file=$name.install ;;
      s) echo "Stopped. Nothing was written."; return 0 ;;
    esac
  fi
  local other_warnings
  other_warnings=$(jq -r '.warnings[] | select((contains("basic C libraries") or contains("run as root")) | not)' <<<"$desc")
  if [[ -n $other_warnings ]]; then
    echo
    echo "Also:"
    sed 's/^/  - /' <<<"$other_warnings"
    confirm "Go on?" y || { echo "Stopped. Nothing was written."; return 0; }
  fi

  # 6. The PKGBUILD -----------------------------------------------------------
  heading "6/7 The PKGBUILD"
  local base upstream_name provides conflicts tag_expr file_expr source_expr template pkgbuild pkgdesc licenses
  base=${name%-gh}
  upstream_name=$(jq -r '.metadata.name // empty' <<<"$desc")
  provides=$({ echo "$base"; echo "$upstream_name"; jq -r '.metadata.provides[]' <<<"$desc" | bare_name; } |
    grep -vxF "$name" | grep -v '^$' | awk '!seen[$0]++' || true)
  conflicts=$({ echo "$upstream_name"; jq -r '.metadata.conflicts[]' <<<"$desc" | bare_name
    echo "$same_app"; } | grep -vxF "$name" | grep -v '^$' | awk '!seen[$0]++' || true)

  tag_expr=${tag/"$version"/'$pkgver'}
  if [[ $file == *"$version"* ]]; then
    file_expr="\"${file/"$version"/'$pkgver'}\""
    source_expr="\"\$url/releases/download/$tag_expr/\$_file\""
  else
    file_expr="\"$name-\$pkgver.pkg.tar.zst\""
    source_expr="\"\$_file::\$url/releases/download/$tag_expr/$file\""
  fi

  pkgdesc=$(jq -r '.metadata.description // empty' <<<"$desc")
  pkgdesc="\"$(dquote_escape "${pkgdesc:-${repo#*/}}") (from the upstream GitHub release)\""
  licenses=$(jq -r '.metadata.licenses[]' <<<"$desc")
  [[ -n $licenses ]] || licenses=$(jq -r '.license // empty | select(. != "NOASSERTION")' <<<"$info")
  [[ -n $licenses ]] || licenses=LicenseRef-unknown

  local license_txt depends_txt optdepends_txt provides_txt conflicts_txt
  array_value license_txt <<<"$licenses"
  array_value depends_txt <<<"$depends"
  array_value optdepends_txt <<<"$optdepends"
  array_value provides_txt <<<"$provides"
  array_value conflicts_txt <<<"$conflicts"

  template=$(<"$GHPKG_SHARE/skill/ghpkg/templates/PKGBUILD.zst")
  [[ -n $install_file ]] || template=$(grep -vxF 'install=@INSTALL@' <<<"$template")
  pkgbuild=$(render_template <(printf '%s\n' "$template") \
    "PROJECT=${repo#*/}" "PKGNAME=$name" "GHREPO=$repo" "PKGVER=$version" "PKGDESC=$pkgdesc" \
    "LICENSE=$license_txt" "DEPENDS=$depends_txt" "OPTDEPENDS=$optdepends_txt" \
    "PROVIDES=$provides_txt" "CONFLICTS=$conflicts_txt" "INSTALL=$install_file" \
    "FILE=$file_expr" "SOURCE=$source_expr" "SHA256=$(jq -r .file.sha256 <<<"$desc")")

  echo "$pkgbuild" | sed 's/^/  │ /'
  echo
  confirm "Save it as $GHPKG_ROOT/$name/PKGBUILD?" y || { echo "Stopped. Nothing was written."; return 0; }
  mkdir -p "$GHPKG_ROOT/$name"
  printf '%s\n' "$pkgbuild" >"$GHPKG_ROOT/$name/PKGBUILD"
  if [[ -n $install_file ]]; then
    {
      echo "# Upstream's .INSTALL from $file, carried over by ghpkg add."
      echo
      jq -r '.scripts[] | select(.name == ".INSTALL") | .text' <<<"$desc"
    } >"$GHPKG_ROOT/$name/$install_file"
  fi
  echo "Saved $GHPKG_ROOT/$name/."

  # makepkg looks for the download under the source's local name.
  local cached=$GHPKG_CACHE/sources/$file local_name
  local_name=$(source_name "$(pkgvar "$name" source | head -1)")
  [[ $local_name == "$file" || -e $GHPKG_CACHE/sources/$local_name ]] || cp "$cached" "$GHPKG_CACHE/sources/$local_name"

  # 7. Test build and install -------------------------------------------------
  heading "7/7 Test build"
  if ! test_build "$name"; then
    echo
    echo "The PKGBUILD is saved but doesn't build yet. Fix it, then run: ghpkg test-build $name"
    return 1
  fi
  echo
  if confirm "Install $name now?" n; then
    require_sudo_terminal "update $name"
    update "$name"
  else
    echo "Install it when you're ready with: ghpkg update $name"
  fi
}

ghpkg_skill_path() { echo "$GHPKG_SHARE/skill/ghpkg"; }
