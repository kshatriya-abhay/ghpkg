# shellcheck shell=bash disable=SC2034 # sets GH_BODY and GH_ERROR for its callers
# Talking to GitHub's API. Requests carry a token when one is available, which
# raises GitHub's limit from 60 requests an hour to 5000.

GITHUB_API=${GITHUB_API:-https://api.github.com}

# Uses GITHUB_TOKEN if set, or else asks `gh` once. The time limit keeps a
# locked keyring from stalling `omarchy update`.
github_token() {
  [[ -n ${GITHUB_TOKEN+set} ]] && return
  GITHUB_TOKEN=$(timeout 5 gh auth token 2>/dev/null) || GITHUB_TOKEN=
}

# GETs an API URL. On success sets GH_BODY; on failure sets GH_ERROR to a
# message a person can act on, and returns 1.
gh_get() {
  local url=$1 out code body auth=()
  GH_BODY='' GH_ERROR=''

  github_token
  if [[ -n $GITHUB_TOKEN ]]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  elif [[ -z ${_ghpkg_token_tip_shown:-} ]]; then
    _ghpkg_token_tip_shown=1
    tip "you aren't logged in to GitHub, which allows 60 requests an hour. Log in with 'gh auth login' (or set GITHUB_TOKEN) for 5000 an hour."
  fi

  # A dead connection gives up after 10 seconds and is tried twice more.
  if ! out=$(curl -sSL --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 1 \
    "${auth[@]}" -H 'Accept: application/vnd.github+json' \
    -w '\n%{http_code}' "$url" 2>/dev/null); then
    GH_ERROR="couldn't reach GitHub"
    return 1
  fi
  code=${out##*$'\n'}
  body=${out%$'\n'*}

  case $code in
    200) GH_BODY=$body ;;
    404) GH_ERROR="not found on GitHub"; return 1 ;;
    401) GH_ERROR="GitHub rejected the token. Check 'gh auth status' or GITHUB_TOKEN."; return 1 ;;
    403 | 429)
      if grep -qi 'rate limit' <<<"$body"; then
        GH_ERROR="GitHub's rate limit is used up. Without a token it allows 60 requests an hour: log in with 'gh auth login' or set GITHUB_TOKEN."
      else
        GH_ERROR="GitHub refused the request (HTTP $code)"
      fi
      return 1
      ;;
    *) GH_ERROR="GitHub answered HTTP $code"; return 1 ;;
  esac
}

# The latest (non-pre-release) release of owner/repo, in RELEASE.
fetch_release() {
  gh_get "$GITHUB_API/repos/$1/releases/latest" || return 1
  RELEASE=$GH_BODY
}

# The checksum GitHub lists for a release file, from RELEASE, without the
# "sha256:" prefix. Empty when GitHub lists none.
asset_digest() {
  local digest
  digest=$(jq -r --arg url "$1" \
    '.assets[] | select((.browser_download_url | ascii_downcase) == ($url | ascii_downcase)) | .digest // empty' <<<"$RELEASE")
  [[ $digest == sha256:* ]] && echo "${digest#sha256:}" || true
}

# A tag as a pkgver: "v1.2.3" and "1.2.3" both give "1.2.3". Fails for tags
# pacman can't use as a version, such as "1.0-beta".
tag_to_pkgver() {
  local version=${1#v}
  [[ -n $version && $version =~ ^[A-Za-z0-9._+]+$ ]] || return 1
  echo "$version"
}
