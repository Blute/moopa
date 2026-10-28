# Agent skills

Moopa's agent skills live in `.agents/skills/` here: how Moopa routes, tables, controls, queries, search and React islands work, and `route-map`, which keeps `route_links.json` current. They are the reference an agent follows before writing Moopa code.

Agents only look for skills in a repository's own `.agents/skills` (Codex, Cursor, OpenCode) and `.claude/skills` (Claude Code), never inside a submodule. A project therefore links each Moopa skill into its own folder:

```txt
.claude/skills                        -> ../.agents/skills
.agents/skills/moopa-routes           -> ../../code/moopa/.agents/skills/moopa-routes
.agents/skills/route-map              -> ../../code/moopa/.agents/skills/route-map
.agents/skills/postmark/              # the project's own skill, a real folder
```

A link means updating the `code/moopa` submodule updates the skill. A copy drifts, so a project never copies or edits a Moopa skill; a change to one is a Moopa pull request.

## Linking

From the project's root:

```sh
bash code/moopa/scripts/link-skills.sh           # replace copies, link new skills, drop stale links
bash code/moopa/scripts/link-skills.sh --check   # report only; exits 1 if a skill is copied or missing
```

Run it after creating a project and after each Moopa update. A project's CI runs `--check` so a copy can't creep back. A copy it replaces is deleted from the working tree; it is in git, so the diff shows what went, and anything project-specific in it belongs in a skill of the project's own.

Git stores the links as symlinks. On Windows, clone with `core.symlinks=true` (and Developer Mode on), or each link checks out as a small text file, which `--check` reports.
