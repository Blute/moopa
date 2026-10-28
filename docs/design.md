# Design

Every Moopa page, the System pages and a project's own, shares one design: one hand-written stylesheet of design tokens, primitives and components, a little vanilla JavaScript with Alpine, and Font Awesome icons. There is no Tailwind, daisyUI or build step. A project makes it its own with a **theme**: a small stylesheet of token overrides. So the System pages and the project's pages look the same, and each project still looks like itself.

| File | What it is |
|---|---|
| `static/moopa.css` | Tokens, then primitives and components, then the shell (sidebar, profile menu, mobile drawer) |
| `static/moopa.js` | `req()`, `window.toast()`, `loadFilters`/`saveFilters`/`clearFilters`, `getInitials`, `prettyDate`, and the shell's behaviour |
| `static/vendor/alpine-3.17.5/` | Alpine and its focus plugin |
| `static/vendor/fontawesome-free-7.3.1/` | Font Awesome Free: solid, regular and brands |
| `tags/moopa_layout.cfm` | The page shell that loads all of the above |
| `lib/system.cfc` | `stylesheets()` (the `<link>`s every page loads), `staticUrl()`, `solidIcon()`, `avatarUrl()` |

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
| `head` | | HTML for `<head>` after the stylesheets: one page's extras (the project's theme is loaded for every page already) |
| `density` | `compact` | `compact` desk density, or `comfortable` |
| `chrome` | `true` | `false` hides the sidebar, for a page shown in a frame or dialog |

The sidebar shows the app's menus, then, for a sysadmin, a dividing line and a System group with Moopa's pages from `sysadmin_nav.json` (never one of the app's navs). It opens by itself on a System page. A sysadmin's profile menu has Re-initialise. The System pages call the layout as `<cfmodule template="/moopa/tags/moopa_layout.cfm">`, so no project tag of the same name can stand in for it there.

The sidebar is dark, so its icons are always solid: `application.lib.system.solidIcon()` turns any style (`fat`, `fal`, `far`, `fad`, sharp ...) into `fa-solid` and keeps brand icons as `fa-brands`. A project's own shell layout should use it for its sidebar too. The System pages load Font Awesome Free, so a Pro-only icon name shows nothing there.

The profile button shows the signed-in profile's picture (its avatar, else its picture) from `application.lib.system.avatarUrl()`, a small square image through the signed-assets Worker, kept in the session for 15 minutes. The picture lies over the initials and removes itself if it fails to load, so the initials show when there is no picture, files are not set up, or the image cannot be fetched.

## Theming

### Three layers, loaded in this order

| Layer | Owner | What goes in it |
|---|---|---|
| `moopa.css` | Moopa | Default tokens, primitives, components and the shell. Fixed once, for every project. |
| The project's **theme** (`theme.css`) | The project | Only `:root { … }` token overrides: its accent, font, sidebar colours, radii. |
| The project's own CSS | The project | Only what Moopa doesn't have: that project's own screens (a kiosk, a docs page). Never a copy or override of Moopa's rules. |

`application.lib.system.stylesheets()` returns the `<link>` tags for the first two layers and the icons, in order. `moopa_layout` puts it in `<head>`; a project's own layout puts it there too, followed by the project's own CSS, so the System pages and the project's pages load the same stack:

```cfml
<head>
    ...
    #application.lib.system.stylesheets()#
    <link rel="stylesheet" href="/_static/app.css?#assetVersion#" />   <!--- the project's own extras, if any --->
</head>
```

### Configuring the theme

In the project's `Application.cfc`, `onApplicationStart` (it may differ per app, as `APP_NAME` is known there):

```cfml
<!--- Both keys are optional --->
<cfset application.moopa_theme = {
    icons: "https://kit.fontawesome.com/<kit>.css",
    css:   [ "/_static/theme.css", "/_static/theme-www.css" ]
} />
```

- **`icons`**: a Font Awesome kit or other icon CSS. Unset, Moopa's vendored Font Awesome Free (solid, regular, brands) loads. A Pro kit makes Pro icon names work on the System pages too.
- **`css`**: the theme files. Unset, Moopa loads `/_static/theme.css` and then `/_static/theme-<app>.css` (for example `theme-www.css`) when they exist, so a project with one theme needs no configuration at all. Each is versioned by its content, so browsers keep it until it changes.

### What a theme sets

```css
/* code/www/_static/theme.css */
:root {
  --signal:         oklch(66% 0.190 45);   /* the accent */
  --signal-deep:    oklch(58% 0.185 45);
  --signal-press:   oklch(50% 0.175 45);
  --signal-soft:    oklch(96% 0.025 45);
  --signal-subdued: oklch(85% 0.090 45);
  --shell-signal:   oklch(74% 0.150 50);   /* the accent on the dark sidebar */
  --font-sans: Inter, "SF Pro Text", "Segoe UI", ui-sans-serif, system-ui, sans-serif;
  --font-features: "ss01", "cv05", "tnum";
}
```

- `--signal` is the one vivid colour, used for state only: the current menu item, focus, links, selected and primary actions. Focus rings derive from it, so re-branding it re-brands focus too. Set its family together: `-deep` (links, text on soft), `-press` (pressed buttons), `-soft` (selected backgrounds), `-subdued` (borders).
- `--font-sans` names the font, `--font-features` its OpenType features, `--heading-tracking` headings' letter-spacing. Moopa loads no web font; a theme that wants one loads it itself (an `@import` or `@font-face` in its theme file).
- The sidebar is a darker panel than the page, for contrast. It has its own tokens (`--shell-bg`, `--shell-bg-raised`, `--shell-line`, `--shell-edge`, `--shell-ink`, `--shell-ink-secondary`, `--shell-ink-mute`, `--shell-signal`, `--shell-danger`); inside the sidebar and the mobile bar the page tokens point at them, so every primitive used there follows. Override the `--shell-*` tokens to re-colour the panel, for example to a light one.
- Everything else is a token too: ink and paper, semantic colours, radii, shadows, spacing, control sizes and density (`[data-density="compact"]`), z-index, chart series. Read the `:root` block at the top of `moopa.css`.

### Rules

1. A theme overrides tokens, never rules. If a theme needs a rule changed, the rule should read a token: add the token to Moopa.
2. Route markup uses Moopa's classes and tokens, never a colour literal or a utility class.
3. A component a second project could use belongs in `moopa.css`, not a project's CSS. Project CSS is for that project's own screens.

### Moving a project onto it

From a copied stylesheet (a project with its own `basic.css` and `shell.css`):

1. Put the project's real differences in `theme.css`: compare its `:root` with Moopa's; usually only the accent and the font differ.
2. Put what only that project has in its own CSS (`app.css`); drop every rule Moopa already has.
3. Its layout loads `system.stylesheets()` then `app.css`, uses `system.solidIcon()` and `system.avatarUrl()`, and keeps the shell markup Moopa's layout uses (`moo-shell-*`). Moopa's `moopa.js` drives the shell.
4. Compare screenshots of every page before and after.

From Tailwind and daisyUI: theme first, then page by page. Map daisyUI's theme colours to tokens in `theme.css` (`primary` to `--signal`, `base-100`/`base-200` to `--surface`/`--canvas`, `base-content` to `--ink`), move the shell to `moopa_layout` or a layout loading `system.stylesheets()`, then rewrite each page's utility classes as Moopa primitives (`card`, `btn`, `field`, `table`, `stack`, `cluster`, `row`…). A page can keep Tailwind's stylesheet loaded after Moopa's until it is rewritten; remove the Tailwind build when the last page is done. A project with several apps (hub, www, agent) gives each its own `theme-<app>.css` where they look different, and shares `theme.css` where they don't.

## Primitives

The class list is the stylesheet's own sections; read them before writing markup, and add a primitive only when a second page needs it (page-specific styles go in a `<style>` block on that page, using tokens).

- **Layout:** `page`, `page-header` (`page-lede`, `page-actions`), `stack`, `cluster`, `row`, `split` (`split-end` puts the aside on the right), `auto-grid` (`--auto-min`)
- **Content:** `card` (`card-header`, `card-title`, `card-sub`, `card-body`, `card-footer`), `stat`, `table` (`table-sm`, `table-hover`, `table-clickable`, `table-fixed`, `table-top`, `cell-main`, `cell-sub`, `actions`, `row-action`), `grid-row` (rows that line up like a table, for trees), `list-rows`, `kv-grid`, `empty`, `code-block`, `code-inline`
- **Controls:** `btn` (`btn-primary`, `btn-ghost`, `btn-danger`, `btn-danger-solid`, `btn-sm`, `btn-xs`, `btn-icon`), `chip`, `field`, `label`, `help`, `input`, `select`, `textarea`, `input-icon`, `input-group`, `switch`, `checkbox`, `radio`, `option`
- **Status:** `badge` (`-success`, `-warning`, `-danger`, `-info`, `-signal`, `-outline`), `dot`, `avatar`, `alert`, `eyebrow`
- **Overlays:** `modal` (a native `<dialog>`: `showModal()` and `close()`; `modal-sm`, `modal-lg`, `modal-xl`, `modal-full`, `modal-header`, `modal-body`, `modal-body-frame`, `modal-footer`), `dropdown` (a native `<details>`; `dropdown-menu-panel`, `dropdown-scroll`), `drawer` (`drawer-backdrop`, `drawer-header`, `drawer-body`), `tabs` (`tab-count`, `.is-attention`), toasts
- **Components:** `combo` (a combobox: `combo-shell`, `combo-chip`, `combo-tools`, `combo-list`, `combo-option`, `combo-group`, `combo-empty`), `dropzone` and `file-list` (`file-item`, `file-icon`, `file-body`, `file-name`, `file-meta`, `file-status`, `file-actions`, `progress`), `sort-list` (`sort-item`, `grip`), `section` (`section-header`, `section-body`), `metrics` (`metric`, `metric-label`, `metric-value`), `stepper`, `signature`, `editable`, `row-list`/`row-item`, `row-card`, `note-list`, `callout`, `swatch`, `terms`, `chart-wrap`, `range-presets`
- **Helpers:** `num`, `money`, `prose`, `kbd`, `field-w-xs`…`field-w-lg`, `input-narrow`, `textarea-auto`, `btn-ink`, `btn-touch`, `card-flat`, `chip-wide`, `chips-alpha`, `table-airy`, `split-wide`, `mt-1`/`mt-3`/`mt-4`

The components' behaviour (open a combobox, drop a file, drag to sort) is the project's Alpine code; Moopa provides the look.

A dialog driven by an Alpine flag follows it with `x-effect="open ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="open = false"`, so Esc and the backdrop keep the flag in step.

## Updating a vendored library

Download the release from npm (`npm pack alpinejs@<version>`), copy the minified build into a new `static/vendor/<name>-<version>/` folder with its licence, point `moopa_layout.cfm` at it, and delete the old folder. The version in the folder name is what lets browsers cache the files for a year.
