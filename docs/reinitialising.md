# Re-initialising an app

A request carrying `?init` restarts the application: `applicationStop()`, so the next request runs `onApplicationStart` again and picks up route, lib and table-definition changes. While it stops, other requests are sent to `/restarting/`.

Who may restart it (`application.cfc` `_reinitAllowed`):

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
