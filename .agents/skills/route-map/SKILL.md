---
name: route-map
description: Keeps each package's route_links.json (which pages every route links to, drawn by Hub's System → Route Access) in step with the routes. Use when adding, moving or deleting a route, changing the links a page renders, or when assert-route-links.py fails.
---

# Route map

`route_links.json` records, for every route a package owns, the routes its page links to. Route Access draws its map from it: each page under the menu item that leads to it, and a warning wherever a role can open a page but not a page it links to. A wrong entry draws a wrong map, so every link is read from the route's own code, never guessed from its name.

**The format is defined once, in `code/moopa/docs/route-links.md`.** Read it first: what a key is, how a URL becomes a route, and what counts as a link. A package opts in by having the file beside its `routes/` folder: `code/apps/<app>/route_links.json`, `code/shared/route_links.json`. An app with no role-gated routes can leave it out.

Paths below are from a project's root. Working in Moopa itself, the package is Moopa's own (`route_links.json` at its root, for the System pages) and the check is `python3 scripts/assert-route-links.py .`.

## Steps

1. **Find the scope.** Run `python3 code/moopa/scripts/assert-route-links.py`. Its *unmapped* and *no route file* lines are routes to add or remove. Add every route whose file this branch changed (`git diff --name-only origin/main...` plus uncommitted changes, under `code/apps/<app>/routes/` or `code/shared/routes/`), and any route a changed tag or include renders into. Asked for a full rebuild, the scope is every route file in the package. Done when you hold a list of route URLs.

2. **Read each route's links.** For each route in scope, read the whole route file, every tag and include it renders, and the page-specific scripts it loads, and list every URL-shaped string, template strings like `` `/customers/${item.id}/customer` `` included. Classify each with the format doc's *What counts as a link*, and resolve each link against the route files themselves: `/customers/${item.id}/customer` is `/customers/[customer_id]/customer` because `routes/customers/[customer_id]/customer.cfc` exists. Done when every URL-shaped string is either recorded or set aside by a named rule of that section.

3. **Write the entries.** Edit the package's `route_links.json`: one key per route in scope, mapped to its links; remove keys for deleted routes, and rename the route everywhere it appears as a link when it moved. Then run `python3 code/moopa/scripts/assert-route-links.py --format`, which sorts and de-duplicates.

4. **Check.** `python3 code/moopa/scripts/assert-route-links.py` exits 0. In the PR description, list the routes whose links changed and every broken link found (a same-app URL with no route file), with its file and line.

## Gotchas

- The System pages (`/sysadmin/*`) are Moopa's, served by Hub from `code/moopa/routes/sysadmin` and listed in `code/moopa/route_links.json`. A project's file never lists them, though Hub's routes may link to them. A project route under `routes/sysadmin` is an error: Moopa refuses to start with one.
- A route reached from several pages lists none of them: links are recorded on the page they appear on, never on their target.
