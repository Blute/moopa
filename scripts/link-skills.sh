#!/usr/bin/env bash
#
# Expose Moopa's agent skills in a project by linking them, so a Moopa update brings the skills
# with it and no project carries a copy that drifts.
#
#   bash code/moopa/scripts/link-skills.sh           # link: replace copies, add new, drop stale
#   bash code/moopa/scripts/link-skills.sh --check   # report only; exit 1 if anything is off (CI)
#
# Run from the project's root. For each skill in code/moopa/.agents/skills/<name>, the project's
# .agents/skills/<name> becomes a symlink to ../../code/moopa/.agents/skills/<name>. A copy in its
# place is deleted (it is in git, so the diff shows exactly what went); a link to a Moopa skill
# that no longer exists is removed. The project's own skills are untouched. .claude/skills is
# linked to .agents/skills if it is missing, so Claude Code sees the same set.
#
# Git stores the links as symlinks. On Windows, check out with core.symlinks=true (and Developer
# Mode), or each link arrives as a small text file, which --check reports.

set -euo pipefail

mode="link"
if [ "${1:-}" = "--check" ]; then
  mode="check"
elif [ -n "${1:-}" ]; then
  echo "usage: link-skills.sh [--check]" >&2
  exit 2
fi

moopa_skills="code/moopa/.agents/skills"
project_skills=".agents/skills"
if [ ! -d "$moopa_skills" ]; then
  echo "No $moopa_skills here. Run from a Moopa project's root, with the code/moopa submodule checked out." >&2
  exit 2
fi

problems=0
report() {
  if [ "$mode" = "check" ]; then
    echo "$1"
    problems=$((problems + 1))
  else
    echo "$2"
  fi
}

mkdir -p "$project_skills"

for source in "$moopa_skills"/*/; do
  name="$(basename "$source")"
  target="../../$moopa_skills/$name"
  path="$project_skills/$name"

  if [ -L "$path" ] && [ "$(readlink "$path")" = "$target" ]; then
    continue
  fi

  if [ -e "$path" ] || [ -L "$path" ]; then
    report "$path is not a link to Moopa's $name skill (a copy, or a link elsewhere)" "replaced $path with a link to Moopa's"
  else
    report "$path is missing (Moopa has a $name skill)" "linked $path"
  fi
  if [ "$mode" = "link" ]; then
    rm -rf "$path"
    ln -s "$target" "$path"
  fi
done

for path in "$project_skills"/*; do
  [ -L "$path" ] || continue
  case "$(readlink "$path")" in
    "../../$moopa_skills/"*)
      if [ ! -e "$path" ]; then
        report "$path links to a Moopa skill that no longer exists" "removed $path (Moopa no longer has it)"
        [ "$mode" = "link" ] && rm "$path"
      fi
      ;;
  esac
done

if [ ! -e .claude/skills ] && [ ! -L .claude/skills ]; then
  report ".claude/skills is missing, so Claude Code sees no skills" "linked .claude/skills to .agents/skills"
  if [ "$mode" = "link" ]; then
    mkdir -p .claude
    ln -s ../.agents/skills .claude/skills
  fi
elif [ ! -L .claude/skills ] || [ "$(readlink .claude/skills)" != "../.agents/skills" ]; then
  echo "warning: .claude/skills is not a link to ../.agents/skills; Claude Code may not see Moopa's skills" >&2
fi

if [ "$mode" = "check" ] && [ "$problems" -gt 0 ]; then
  echo
  echo "Moopa's skills are copied or missing. Run: bash code/moopa/scripts/link-skills.sh"
  exit 1
fi
exit 0
