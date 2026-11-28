# Project rules

How every Moopa project is worked on, whoever hosts it. These are the rules for work *in a project*. Moopa's own
[AGENTS.md](../AGENTS.md) is the rules for work on Moopa itself, and doesn't apply to projects.

## Three layers

A project's rules come in three layers, all in its checkout, read in this order:

1. **Moopa's:** this file, at `code/moopa/docs/project-rules.md` in every project. It changes when the project moves
   its Moopa submodule.
2. **The operator's:** `OPERATOR-RULES.md` at the project's root. The operator is the organisation that owns the
   project's repository and hosts it. The file is the same in all its projects, and changes by pull request to all
   of them.
3. **The project's:** the top of its `AGENTS.md`.

Where two layers disagree, the later, more specific one wins.

## Overrides

A layer changes a rule from an earlier layer only with an override that names the rule it replaces and says why:

> Replaces *Database changes are additive only*: this project has no production data until it launches on 1 March;
> until then a change may drop or rename columns.

A rule a later layer doesn't mention is inherited. Leaving a rule out, or rewording it, overrides nothing.

## Floor rules

No layer may override these. Each is a moment where the user says yes, so a rule that removed one couldn't be
approved by the process it removes. An override of a floor rule is invalid wherever it appears, including in the
branch being worked on.

1. **Never merge without the user's permission.**
2. **Never commit, print, put in chat or pass as a command-line argument a secret.** A secret moves only along the
   paths built for it, which the operator's rules list.
3. **No SQL against a hosted database without the user's go-ahead for that exact SQL,** the SQL System → Schema
   generates included.
4. **No apply, destroy or import of hosting infrastructure, and no change to its state, without the user's
   go-ahead.**

## Quality

- Correctness over speed. No shortcuts, workarounds, monkey patches or partial solutions. If the right support is
  missing, add it properly, or say the task is blocked and why.
- Fail clearly. Never silently skip an error, a missing field, a missing template or invalid state.
- Correct design beats compatibility with internal code. Data is different: see the database rules below.
- After each change, report anything you aren't fully confident about, anything fragile or that could be seen as a
  shortcut, any deliberate change in behaviour, and anything needing follow-up. When there's none, say so.

## Production

Once a project is hosted, every merge to its default branch goes to production, and its database holds the
client's real data.

- **Database changes are additive only:** new tables, columns, indexes, functions and defaults. Never drop, rename
  or retype a column, or delete or rewrite data, as part of a change. Removing something is a separate change, made
  after nothing uses it, and only when the user explicitly approves it.
- **Stage environments are rare.** Turn one on only when the user explicitly asks.

## Keep the database asleep

A hosted database that suspends when idle bills its compute only while it's awake. Anything that queries it on a
clock, or for every visitor, keeps it awake and is paid for every hour of every day.

- Never add anything that keeps the database awake without the user's deliberate decision that this specific thing
  may. A go-ahead for the feature isn't that decision: say what will wake the database and how often, and ask.
- That covers:
  - a scheduled job that touches the database, or an existing one run more often;
  - database writes, or reads beyond the data the page shows, on public pages (page-view counts, analytics, visit or
    request logs, rate limits, audit rows), which every bot and visitor would trigger;
  - writing the session for visitors who aren't signed in;
  - polling, keep-alives or health checks that query the database;
  - the engine's own background work on the database. RustCFML, with sessions stored in the database, removes
    expired sessions on a 60-second clock unless `code/www/.cfconfig.json` turns that off:
    `"session": {"reapIntervalSecs": 0}`. Without that setting the database is queried every minute and never
    sleeps. The starter has it; keep it, and check it in any project that didn't come from the starter.
- Put such work where it needs no database: in memory, at the edge, or done when someone asks for it rather than on
  a clock.
- When the user does decide, say so in a comment beside the job or the code, naming the decision, so it isn't read
  as precedent.

## Environment, secrets and email

- A hosted project's environment and secrets belong to its operator's infrastructure, not to the project. Never set
  them in a host's dashboard, and never commit them. A new environment variable is a change in two places: the code
  that reads it, in the project, and its value, in the operator's infrastructure.
- `.env` (not committed) holds local development values only.
- Everything a project sends goes through `application.lib.email` ([email](email.md)). How it's delivered and who
  it's from belong to the infrastructure: never add a mail provider's library or `cfmail` to a project, and never
  choose the provider or the From address in project code.

## Git workflow

- Work on a branch named for the change, and open a pull request when the work is ready.
- Wait for the operator's review bot. Fix what it finds and push until it comes back clean. Then ask the user for
  permission to merge (floor rule 1).
- Never push to the default branch, force-push a shared branch or rewrite published history.
- Never commit `.env`, secrets, database dumps or client data.
- Moopa changes by pull request to Moopa, never by editing the `code/moopa` submodule. Moopa is public, so keep the
  project's name, hostnames and data out of its issues, pull requests, commits and branch names.
