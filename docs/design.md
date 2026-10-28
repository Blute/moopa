# Design

Moopa's own pages, the System pages, use Moopa's own design: one hand-written stylesheet of design tokens and primitives, a little vanilla JavaScript with Alpine, and Font Awesome Free icons. There is no Tailwind, daisyUI or build step, and nothing is loaded from another origin. A project page can opt in to the same layout and primitives.

| File | What it is |
|---|---|
| `static/moopa.css` | Tokens, then primitives, then the shell (sidebar, profile menu, mobile drawer) |
| `static/moopa.js` | `req()`, `window.toast()`, `loadFilters`/`saveFilters`/`clearFilters`, `getInitials`, `prettyDate`, and the shell's behaviour |
| `static/vendor/alpine-3.17.5/` | Alpine and its focus plugin |
| `static/vendor/fontawesome-free-7.3.1/` | Font Awesome Free: solid, regular and brands |
| `tags/moopa_layout.cfm` | The page shell that loads all of the above |

Moopa serves `static/` itself at `/_moopa/static/…`, answered before the session or database is touched. `application.lib.system.staticUrl(path)` gives a file's URL versioned by the content of `moopa.css` and `moopa.js`, and versioned URLs and the `vendor/` folders are cached for a year. Only files under `static/` with a known extension are served.

## The layout

```cfml
<cf_moopa_layout title="Orders">
    <div class="page">
        <div class="page-header">
            <div>
                <div class="eyebrow">12 open</div>
                <h1>Orders</h1>
                <p class="page-lede">What's waiting to be picked.</p>
            </div>
            <div class="page-actions"><button class="btn btn-primary btn-sm">New order</button></div>
        </div>
        <div class="card">…</div>
    </div>
</cf_moopa_layout>
```

| Attribute | Default | |
|---|---|---|
| `title` | | The page's title, after the project's in the browser tab |
| `current` | this route | The route to mark current in the menus |
| `navs` | every nav file, by name | Nav files to show in the sidebar, in order |
| `head` | | HTML for `<head>` after Moopa's stylesheet: token overrides, extra scripts |
| `density` | `compact` | `compact` desk density, or `comfortable` |
| `chrome` | `true` | `false` hides the sidebar, for a page shown in a frame or dialog |

The sidebar shows the app's menus. A sysadmin's profile menu lists the System pages from `sysadmin_nav.json`; they are never in the sidebar. The System pages call the layout as `<cfmodule template="/moopa/tags/moopa_layout.cfm">`, so no project tag of the same name can stand in for it there.

The sidebar's icons are Font Awesome Free. A menu item using a Pro style (`fat`, `fal`, `fad`, sharp) falls back to the Free solid icon of the same name, which shows if Free has that icon.

## Theming

Every colour, radius, size and spacing is a custom property in the `:root` block at the top of `moopa.css`. Route markup uses the primitives and tokens, never a colour literal. A project re-brands by overriding tokens, for example through the layout's `head`:

```cfml
<cf_moopa_layout title="Orders" head="<style>:root { --signal: oklch(55% 0.18 150); --signal-deep: oklch(47% 0.17 150); --signal-soft: oklch(97% 0.02 150); --signal-subdued: oklch(84% 0.07 150); }</style>">
```

`--signal` is the one vivid colour, used for state only: the current menu item, focus, links, selected and primary actions. Focus rings derive from it, so re-branding it re-brands focus too.

## Primitives

The class list is the stylesheet's own sections; read them before writing markup, and add a primitive only when a second page needs it (page-specific styles go in a `<style>` block on that page, using tokens).

- **Layout:** `page`, `page-header` (`page-lede`, `page-actions`), `stack`, `cluster`, `row`, `split` (`split-end` puts the aside on the right), `auto-grid` (`--auto-min`)
- **Content:** `card` (`card-header`, `card-title`, `card-sub`, `card-body`, `card-footer`), `stat`, `table` (`table-sm`, `table-hover`, `table-clickable`, `table-fixed`, `table-top`, `cell-main`, `cell-sub`, `actions`, `row-action`), `grid-row` (rows that line up like a table, for trees), `list-rows`, `kv-grid`, `empty`, `code-block`, `code-inline`
- **Controls:** `btn` (`btn-primary`, `btn-ghost`, `btn-danger`, `btn-danger-solid`, `btn-sm`, `btn-xs`, `btn-icon`), `chip`, `field`, `label`, `help`, `input`, `select`, `textarea`, `input-icon`, `input-group`, `switch`, `checkbox`, `radio`, `option`
- **Status:** `badge` (`-success`, `-warning`, `-danger`, `-info`, `-signal`, `-outline`), `dot`, `avatar`, `alert`, `eyebrow`
- **Overlays:** `modal` (a native `<dialog>`: `showModal()` and `close()`; `modal-sm`, `modal-lg`, `modal-xl`, `modal-header`, `modal-body`, `modal-footer`), `dropdown` (a native `<details>`), `tabs`, toasts

A dialog driven by an Alpine flag follows it with `x-effect="open ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="open = false"`, so Esc and the backdrop keep the flag in step.

## Updating a vendored library

Download the release from npm (`npm pack alpinejs@<version>`), copy the minified build into a new `static/vendor/<name>-<version>/` folder with its licence, point `moopa_layout.cfm` at it, and delete the old folder. The version in the folder name is what lets browsers cache the files for a year.
