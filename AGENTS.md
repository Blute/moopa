# Rules for agents

Moopa is a CFML framework on the RustCFML engine: file-based routes, table definitions, PostgreSQL, Alpine.js and its own vanilla-CSS design system. Projects use it as a git submodule at `code/moopa`, and link its skills into their own `.agents/skills`. `CLAUDE.md` is a symlink to this file.

## This repository is public

- Keep everything about clients and private projects out of it: names, hostnames, email addresses, private repository names, screenshots and data. That covers code, comments, docs, skills, issues, pull request text, commit messages and branch names.
- Use generic examples: `<client>`, `example.com`, `you@example.com`. Describe why a change is needed without saying whose project needed it.
- Never commit secrets, `.env` files or real configuration values.

## Before changing anything

- Read [README.md](README.md) and the doc for the area you are changing (`docs/`). UI work follows [docs/design.md](docs/design.md): Moopa's classes and tokens, no utility classes, no CSS build.
- Check `.agents/skills/` for a skill that covers the task, and follow it. A skill that is wrong gets fixed here, in the same pull request as the code it describes.
- Keep a doc or skill current in the same pull request that changes the behaviour it describes.

## Production apps run this code

Every project picks up a Moopa change when it moves its `code/moopa` submodule, and those projects run in production.

- **Database changes are additive only:** new tables, columns, indexes, functions and defaults. Never drop, rename or retype a column, or remove or rewrite data, as part of a change. Removing something is a separate, deliberate change after nothing uses it any more.
- A change that needs a project to do something when it updates (new environment variables, a setting, a Worker redeploy) says so in its doc's upgrade section and in the pull request under **After merging**.
- Fail loudly on missing configuration rather than falling back silently.

## Git workflow

- Never push to `main`. Work on a branch named for the change, and open a pull request.
- Wait for the Cursor Bugbot review, fix what it finds, and push until it comes back clean. Then ask the user for permission to merge. Never merge without it.
- Never force-push a shared branch or rewrite history.
- Pull request text: what changed, why, and how it was checked, plus **After merging** when projects must act. Generic wording only (see above).
