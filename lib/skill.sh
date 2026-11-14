# shellcheck shell=bash
# skill: make the ghpkg agent skill available to coding agents, by linking it
# into each agent's skills folder. The same three places Omarchy links its own
# skills into.

skill_dirs() {
  local home
  for home in "$HOME/.claude" "$HOME/.codex" "$HOME/.agents"; do
    [[ -d $home ]] && echo "$home/skills"
  done
  return 0
}

skill() {
  local action=${1:-} src=$GHPKG_SHARE/skill/ghpkg dir found=false
  [[ -f $src/SKILL.md ]] || die "can't find the skill's files: $src/SKILL.md is missing"

  case $action in
    path)
      echo "$src"
      ;;
    install)
      while IFS= read -r dir; do
        found=true
        mkdir -p "$dir"
        if [[ -e $dir/ghpkg && ! -L $dir/ghpkg ]]; then
          warn "$dir/ghpkg already exists and isn't a link, so it was left alone"
          continue
        fi
        ln -sfn "$src" "$dir/ghpkg"
        echo "Linked $dir/ghpkg -> $src"
      done < <(skill_dirs)
      $found || {
        echo "No agent folders found (~/.claude, ~/.codex or ~/.agents)."
        echo "Point your agent at the skill's folder: $src"
      }
      ;;
    remove)
      while IFS= read -r dir; do
        if [[ -L $dir/ghpkg && $(readlink -f "$dir/ghpkg") == "$(readlink -f "$src")" ]]; then
          rm "$dir/ghpkg"
          echo "Removed $dir/ghpkg"
          found=true
        fi
      done < <(skill_dirs)
      $found || echo "The skill wasn't linked anywhere."
      ;;
    *)
      die "usage: ghpkg skill install | remove | path"
      ;;
  esac
}
