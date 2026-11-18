# Impersonation

An impersonation link signs a browser in as someone else, to see the app as they do. Hub's **System → Impersonation** page makes one: pick the person, and the link is copied to the clipboard. It works once, within 5 minutes of being made.

**Opening the link changes nothing.** It shows who made it and who it signs in as, with a **Continue as <name>** button. Only the button (a POST) uses the link. Link previews (WhatsApp, Slack, iMessage) and mail scanners open links before the person does; a link that worked on opening was spent by them, and the person got "expired". So a link can be pasted into a private window, or sent by chat or email.

The session it starts doesn't stay signed in: closing the browser ends it, as does **End session** on the banner every Moopa page shows while impersonating ("Impersonating <name>, by <name>"). Any 30-day sign-in the browser had is forgotten first, so when the session ends the browser is signed out rather than back in as whoever used it before.

It lives in `lib/impersonation.cfc` (`application.lib.impersonation`). The link itself is a login grant of kind `impersonation` (`lib/login_grant.cfc`, table `moo_login_grant`), which also feeds the System page's recent activity.

## A project's route

The project's `/auth/impersonate/` route, in its shared package so every app serves it, hands its `get` and `post` to Moopa:

```cfml
<!--- code/shared/routes/auth/impersonate.cfc --->
<cfcomponent key="…" open_to="public">
    <cffunction name="get"><cfreturn application.lib.impersonation.get() /></cffunction>
    <cffunction name="post"><cfreturn application.lib.impersonation.post() /></cffunction>
</cfcomponent>
```

After the button, the browser goes to the impersonated person's app's home: `application.app_homes[<their app>]` when the project sets it, else `/`.

## Who may make a link, and for whom

- **Who:** anyone with access to the `create_grant` endpoint of `/sysadmin/impersonation/` (granted on the System page), and the hub's sysadmins.
- **For whom:** a profile that can sign in, except the hub's sysadmins (`SYSADMIN_EMAIL`).
- **Its address** is the impersonated person's app's, by the same rule as sign-in links: `application.app_base_urls[<their app>]`, else `BASE_URL` ([signin.md](signin.md), Configuration). Never the request's `Host` header.

## In code

| | |
| --- | --- |
| `createGrant(target_profile_id)` | A new link for the signed-in profile: `{ success, url }`. Throws when they may not make one, or the target can't be impersonated. |
| `get()`, `post()` | The route's handlers. A link that's unknown, used or expired gets a page saying so; any other failure is an ordinary error ([errors.md](errors.md)). |
| `isImpersonating()` | Whether this session was started by an impersonation link. |
| `impersonator()` | Who started it: `{ id, full_name, email, mobile }`, or `{}`. |

## Upgrading an existing app

Projects made before this kept impersonation in their own `code/shared/lib/impersonate.cfc`, with a table `moo_impersonation_grant` and a route that used the link on opening. Moopa's System page now makes links with `application.lib.impersonation`, so after updating Moopa:

1. Replace the body of `code/shared/routes/auth/impersonate.cfc` with the two handlers above. Until then, links from the System page land on "expired".
2. Delete `code/shared/lib/impersonate.cfc`, after moving any other use of it to `application.lib.impersonation` (`isImpersonating()`, `impersonator()`).
3. Check the database has `moo_login_grant` (System → Schema). The System page's activity already reads it, so most apps do.
4. Keep the `moo_impersonation_grant` table and its definition for now. Removing them is a change of its own.
