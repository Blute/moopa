# Re-initialising an app

A request carrying `?init` restarts the application: `applicationStop()`, so the next request runs `onApplicationStart` again and picks up route, lib and table-definition changes.

## Requests still running

Stopping the application empties its scope, including under requests that are still running: their next `application.lib` lookup would fail part-way through. So `?init`:

1. sends every new request to `/restarting/`,
2. waits for the requests already running to finish, up to 30 seconds (`REINIT_WAIT_SECONDS`),
3. stops the application once none is left.

If any are still running after 30 seconds, the application is **not** stopped. `?init` answers **503** naming each one and how long it has run, and new requests go through again. Try again once they finish.

Moopa counts a request as running from `OnRequestStart` until it leaves by one of the three ways a request ends: `OnRequestEnd`, `onAbort` (a `cfabort` or `cflocation`, which every endpoint ends with) or `OnError`. So a project's `Application.cfc`:

- overriding `OnRequestStart`, `OnRequestEnd` or `onAbort` calls `super`;
- changing how errors are answered overrides `handleError(Exception, EventName)`, calling `super.handleError` for errors it leaves to Moopa, and never overrides `OnError`.

A request that leaves without passing through one of these is counted as running until the server restarts, and every `?init` after it answers 503 naming it.

Work running outside a request, such as a `cfthread` that outlives the request that started it, isn't counted, and a restart can still empty the scope under it.

### Upgrading

A project whose `Application.cfc` overrides `OnError` moves that code into `handleError`, calling `super.handleError` where it called `super.OnError`.

## Who may restart it

As `application.cfc`'s `_reinitAllowed` decides:

| Environment | Allowed |
|---|---|
| `APP_ENVIRONMENT` exactly `development` | Any request, GET included: `curl -sk "https://<app>.local/?init"` |
| Anything else | A **POST** carrying the init key, or made through `req()` by a sysadmin signed in to this app |

Everything else is refused with **403** and the application keeps running.

- **Sysadmins** use the Re-init button (System → Schema), or from any page:

  ```js
  await req({ url_params: { init: "1" }, body: {} });
  window.location.reload();
  ```

  It has to be a `req()` call: `req()` sends `X-Fetch-Request`, which a page on another site cannot send, so a link or form elsewhere cannot restart the app through a sysadmin's session.

- **Operators** send the init key, `PROJECT_INIT_KEY` in the app's environment, in a header. It is never read from the query string, which access logs record.

  ```bash
  curl -s -X POST -H "X-Moopa-Init-Key: $PROJECT_INIT_KEY" "https://<app-host>/?init"
  ```

  This is the only way in for apps without sysadmins. Without `PROJECT_INIT_KEY` set, the key path is closed.

A GET is answered with a redirect back to the page (a path on this site only); a POST with `{"success": true}` JSON.
