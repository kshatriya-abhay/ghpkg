# shellcheck shell=bash
# hook: run ghpkg at the end of every `omarchy update`, on Omarchy. Either it
# lists what can be updated (the default), or it installs the updates too.

omarchy_hook_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/post-update.d"; }

is_omarchy() {
  command -v omarchy >/dev/null || [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy ]]
}

hook() {
  local action=${1:-} dir src name other
  dir=$(omarchy_hook_dir)
  src=$GHPKG_SHARE/integrations/omarchy

  case $action in
    install)
      is_omarchy || die "the hook is for Omarchy (omarchy.org), and this doesn't look like an Omarchy system"
      case ${2:-} in
        '') name=ghpkg-check-update.hook other=ghpkg-update.hook ;;
        --update) name=ghpkg-update.hook other=ghpkg-check-update.hook ;;
        *) die "usage: ghpkg hook install [--update]" ;;
      esac
      [[ -f $src/$name ]] || die "can't find $src/$name"
      mkdir -p "$dir"
      rm -f "$dir/$other"
      install -m755 "$src/$name" "$dir/$name"
      if [[ $name == ghpkg-update.hook ]]; then
        echo "Installed $dir/$name: every omarchy update now ends by installing new releases of your ghpkg packages. pacman still asks before changing anything."
      else
        echo "Installed $dir/$name: every omarchy update now ends with a list of your ghpkg packages that can be updated."
      fi
      ;;
    remove)
      local removed=false
      for name in ghpkg-check-update.hook ghpkg-update.hook; do
        [[ -f $dir/$name ]] && { rm "$dir/$name"; echo "Removed $dir/$name"; removed=true; }
      done
      $removed || echo "No ghpkg hook was installed."
      ;;
    status)
      for name in ghpkg-check-update.hook ghpkg-update.hook; do
        [[ -f $dir/$name ]] || continue
        local flag=
        [[ $name == ghpkg-update.hook ]] && flag=' --update'
        if cmp -s "$dir/$name" "$src/$name"; then
          echo "Installed: $dir/$name"
        else
          echo "Installed: $dir/$name (it differs from this ghpkg's copy: run 'ghpkg hook install$flag' to update it)"
        fi
        return 0
      done
      echo "Not installed. Run 'ghpkg hook install' to list updates after every omarchy update."
      ;;
    *)
      die "usage: ghpkg hook install [--update] | remove | status"
      ;;
  esac
}
