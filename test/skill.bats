#!/usr/bin/env bats
# skill: linking the agent skill into agents' skill folders.

load helpers

setup() {
  setup_ghpkg
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
}

@test "the skill's files are all there" {
  for file in SKILL.md zst.md deb.md dependencies.md fixing-updates.md \
    templates/PKGBUILD.zst templates/PKGBUILD.deb templates/pkgname.install; do
    [[ -f $REPO_DIR/skill/ghpkg/$file ]] || { echo "missing $file"; false; }
  done
  head -3 "$REPO_DIR/skill/ghpkg/SKILL.md" | grep -qx 'name: ghpkg'
}

@test "install links the skill into each agent folder that exists" {
  mkdir -p "$HOME/.claude" "$HOME/.agents"
  run ghpkg skill install
  [[ $status -eq 0 ]]
  [[ $(readlink -f "$HOME/.claude/skills/ghpkg") == "$REPO_DIR/skill/ghpkg" ]]
  [[ $(readlink -f "$HOME/.agents/skills/ghpkg") == "$REPO_DIR/skill/ghpkg" ]]
  [[ ! -e $HOME/.codex ]]
}

@test "install leaves a real folder of the same name alone" {
  mkdir -p "$HOME/.claude/skills/ghpkg"
  run ghpkg skill install
  [[ $output == *"isn't a link, so it was left alone"* ]]
  [[ ! -L $HOME/.claude/skills/ghpkg ]]
}

@test "install with no agent folders says where the skill is" {
  run ghpkg skill install
  [[ $status -eq 0 ]]
  [[ $output == *"No agent folders found"*"$REPO_DIR/skill/ghpkg"* ]]
}

@test "remove takes away only ghpkg's own links" {
  mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills/ghpkg"
  ghpkg skill install
  run ghpkg skill remove
  [[ $status -eq 0 ]]
  [[ ! -e $HOME/.claude/skills/ghpkg ]]
  [[ -d $HOME/.codex/skills/ghpkg ]]
}

@test "path prints the skill's folder" {
  run ghpkg skill path
  [[ $output == "$REPO_DIR/skill/ghpkg" ]]
}
