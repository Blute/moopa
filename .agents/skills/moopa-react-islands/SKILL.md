---
name: moopa-react-islands
description: Build React mounts for Moopa's server-rendered CFML routes using the `cf_react_mount` tag, route-local JSX sources, and checked-in browser bundles.
---

# Moopa React Islands

Use this pattern when a Moopa page is mostly server rendered but a specific section needs richer client-side interaction.

## Goals

- Keep HTML server rendered first.
- Preserve SEO and no-JS fallback content.
- Mount React only inside targeted islands.
- Keep JavaScript scoped to the component that needs it.

## Paths

Route-local source lives beside the route:

```text
code/apps/{app}/routes/{route}/react/{component}.jsx
```

Served browser bundle mirrors the route path under the webroot:

```text
code/www/_static/react/{app}/{route}/react/{component}.js
```

Example:

```text
code/apps/hub/routes/react/welcome_actions.jsx
code/www/_static/react/hub/react/welcome_actions.js
```

## Custom Tag

Use the shared/project `react_mount.cfm` custom tag via `<cf_react_mount>`:

```cfml
<cf_react_mount
    component="welcome_actions"
    route_path="hub"
    minimum_time="1000"
    props="#serializeJSON(islandProps)#">

    <!--- Server-rendered fallback markup --->

</cf_react_mount>
```

The tag renders:

- a container with `data-react-mount`
- serialized props in `data-props`
- fallback HTML inside the container
- a module script for `/_static/react/{route}/react/{component}.js`

It also tracks emitted scripts in `request.react_mount_scripts` so the same mount script is only added once per request.

### Minimum Display Time

Use `minimum_time` (milliseconds) when you want the server-rendered fallback to remain visible briefly before React replaces it.

This is useful when:

- the fallback intentionally matches the final island header or shell
- immediate mount would cause a distracting flicker
- you want loading states to feel deliberate rather than accidental

Example:

```cfml
<cf_react_mount
    component="welcome_actions"
    minimum_time="1000"
    props="#serializeJSON(islandProps)#">
```

The tag stores timing metadata on the island element, and the island bundle should respect that delay before calling `createRoot(...).render(...)`.

## Route Path Rule

The router now sets `request.current_route_path` for the page route from `route_data.stRoute.componentPath`, so dynamic routes keep their source-style path such as `orders/[order_id]`.

Pass `route_path` explicitly only when you need to override that default.

## Fallback HTML

Always include meaningful fallback content inside the tag when the content matters for:

- SEO
- accessibility
- no-JS usage
- perceived performance before hydration

React should enhance or replace that block after mount.

## Build Workflow

React islands are bundled locally from route-local source in package route folders such as `code/apps/{app}/routes`, `code/shared/routes`, and `code/moopa/routes` into served browser files.

Commands:

```bash
npm run build:react-mounts
npm run watch:react-mounts
```

Local Docker compose runs React mounts in a dedicated `react_mounts` watcher service, separate from the existing frontend asset watcher.

Source remains canonical in `code/apps/{app}/routes/**/react/*.jsx`, `code/shared/routes/**/react/*.jsx`, or `code/moopa/routes/**/react/*.jsx`, and the generated browser bundle is written to the mirrored path under `code/www/_static/react/**/react/*.js`.

Generated bundles include a small header comment so it is obvious they are build artifacts.

If two island sources would generate the same output path, the builder keeps running and emits a safe fallback bundle that leaves the server-rendered markup in place and shows a neutral unavailable message instead of mounting React.

When using shadcn-style components inside islands, keep the copied UI primitives local to the route's `react/` folder and make sure the relevant Tailwind entry file scans `.jsx`/`.tsx` island sources with `@source`.

For richer widgets like comboboxes, prefer the standard shadcn pattern of local `Popover` + `Command` primitives rather than adding a whole client app shell.

When bringing in a shadcn preset, store the resolved semantic tokens as a local preset object and feed them into the island root (and any portal-based overlay content) via CSS variables so components can use `var(--primary)`, `var(--card)`, `var(--border)`, and related semantic tokens consistently.

## Mount Pattern

Each island bundle should:

1. find all matching `[data-react-mount="..."]` nodes
2. parse `element.dataset.props`
3. create a React root for each node
4. render the component with those props

Example:

```javascript
document
  .querySelectorAll('[data-react-mount="hub/react/welcome_actions"]')
  .forEach((element) => {
    const props = JSON.parse(element.dataset.props || "{}");
    createRoot(element).render(<WelcomeActions {...props} />);
  });
```

## Good Use Cases

- comboboxes
- searchable selects
- date pickers
- floating popovers
- command palettes
- drag and drop editors
- richer dashboards with local interactive state

## Avoid Islands For

- plain text inputs
- simple server-rendered forms
- content that can be handled cleanly with standard CFML or Alpine

## Checklist

- source JSX added under the relevant package route folder, e.g. `code/apps/{app}/routes/.../react/`
- served JS added under `code/www/_static/react/.../react/`
- route uses `<cf_react_mount>`
- fallback HTML is present and useful
- script only mounts the intended island key
- props are JSON serializable
