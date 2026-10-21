# Route links

`route_links.json` records which pages a package's routes link to. The Route Access page uses it to draw each route under the pages that lead to it, and to warn when a role can open a page but not a page it links to.

The file is optional. A package that has one declares every route it owns; a route missing from the map shows as **unmapped**.

## Location

One file per package, at the package root, beside `routes/`:

```
apps/<app>/route_links.json
shared/route_links.json
moopa/route_links.json      # the framework's own System routes
```

Not in `navs/`: every `*.json` there loads as a menu.

## Shape

One key per route the package owns, mapped to the sorted list of routes that page links to:

```json
{
  "/": ["/customers/[customer_id]/customer"],
  "/customers": ["/customers/[customer_id]/customer", "/customers/new"],
  "/customers/[customer_id]/customer": [
    "/customers",
    "/customers/[customer_id]/edit",
    "/orders/[order_id]/order"
  ],
  "/customers/[customer_id]/edit": ["/customers/[customer_id]/customer"],
  "/customers/new": [],
  "/login": [],
  "/orders/[order_id]/order": ["/customers/[customer_id]/customer"]
}
```

- **Keys** are the package's routes, written as Moopa registers them: the path under `routes/` with `.cfc` removed and a trailing `/index` dropped (`routes/index.cfc` is `/`). Dynamic segments keep their folder names: `[customer_id]`.
- **Every route file in the package is a key**, including routes outside role security (`public`, `bearer`, `logged_in`). A route that links nowhere maps to `[]`. Routes a package reaches through a symlink into another package (the Hub's `routes/sysadmin`) belong to that other package's file.
- **Values** are the routes Moopa's matcher resolves the link's URL to. The query string, any `#fragment` and a trailing slash are dropped; an exact static route wins, otherwise the dynamic route whose fixed segments match: `/customers/42/customer/?tab=orders` is `/customers/[customer_id]/customer`, whatever the `[...]` folder is called. Shared routes the app serves are routes like any other.
- Keys and values are sorted, values have no duplicates, and a route never lists itself.

## What counts as a link

A link takes the browser from this route's page to another route's page in the same app:

- `<a href>` and Alpine `:href`, including URLs built in template strings, server-side values and helper functions: follow the value to wherever it is built
- `window.location` / `location.href` / `window.open`, `<cflocation>`, and a `<form>` whose submission loads another route
- pages embedded in an `<iframe src>`
- the same, in the tags, includes and page-specific scripts the route renders or loads, recorded against the route
- every target code can produce: a link chosen by status, or shown only when a check finds something, records each route it can land on
- a link to the page's parent list: it is a different route from the page itself

The rest stays on this page or leaves the app, so it is not a link:

- `req()`, `fetch()` and other requests for data, even to another route's endpoint
- anything addressing this page itself: its endpoints, `#` fragments, `history` changes, `<form method="dialog">`
- the app layout tag and its menus, which the menu files describe
- URLs of another app or an external service, static and asset URLs, `mailto:`/`tel:`, `<iframe srcdoc>`, and URLs only copied to the clipboard
- a return address only known at run time (where to go after sign-in); its literal fallback is a link

A same-app URL with no route file behind it is a broken link, not an entry: leave it out and report it.

## Where it shows

**System → Route Access** (`/sysadmin/route_access`) merges every package's file in load order; a later package's entry for the same route wins, as with navs. The page lists any key or link that names a route the app doesn't serve, and shows routes missing from every file as **Unmapped**.

## Validation

A package's map is valid when:

1. its keys are exactly the package's route files: none missing, none left over from deleted routes;
2. every value is a route served by every app that loads the package;
3. keys and values are sorted and unique, and no route lists itself.
