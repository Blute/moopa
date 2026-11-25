# How a request reaches a route

A request that isn't for a file in the web root reaches Moopa through RustCFML's front-controller fallback, set in the project's `code/www/.cfconfig.json`:

```json
"fallback": {
  "template": "_moopa.cfm",
  "routeParam": "route"
}
```

The engine runs `_moopa.cfm` and puts the request's path in `url.route`, ahead of the request's own query string. Moopa's `onRequest` sees `/_moopa.cfm` and runs the route `url.route` names.

The site's home page is the web root's `index.cfm`, which the engine serves for `/`. Moopa runs the `/` route for it, whatever its query string says.

Those two files, at the web root, are Moopa's only ways in. Any other `.cfm` file in the web root (a health check, a test page) runs as itself, and a path that ends in `index.cfm` or `_moopa.cfm` anywhere else is an ordinary path: the fallback routes it like any other, and it matches no route.

## A visitor's `?route=` doesn't choose the route

On every path above, the route is the request's path. A `route` parameter a visitor adds to the query string doesn't change it: on `/` it is ignored, and on any other path it is added after the path the engine put there, so `url.route` matches no route and the request answers 404.

So the path a proxy, firewall or log in front of the app sees is the route Moopa runs, with one exception: a request for `/_moopa.cfm` itself. The engine serves that file like any other, so the visitor's own `?route=` is the only one, and RustCFML gives the page no way to tell it apart from the fallback. Rules in front of the app that decide by path should therefore treat `/_moopa.cfm` as able to reach any route (refuse it, since nothing links to it), and access control belongs in the route itself (`open_to`, [route access](route-access.md)), not in path rules alone.

### Upgrading

Before this change, a request for `/index.cfm?route=/some/route/`, or for any path ending in `/index.cfm` or `/_moopa.cfm` on an engine that passes a missing page to `onRequest`, ran the route it named. Moopa never builds such a link. A project that does (search with `git grep -n "index.cfm?"`) links to the route's own path instead.
