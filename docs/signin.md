# Sign-in

Moopa signs people in without passwords. They enter their email; Moopa emails them a link; opening it on any device (a phone is fine) shows which device asked to sign in, with **Approve** and **Not me**. The page they asked from checks every 2 seconds while it's on screen (not while its tab is hidden, so the database can rest), notices within a couple of seconds and offers **Continue**, which signs that browser in for 30 days.

It lives in `lib/signin.cfc` (`application.lib.signin`) and the table `moo_signin_request`. Its pages render in `tags/moopa_bare.cfm`'s split layout: a "Welcome back" panel in the project's shell colours and logo beside the step, which on a phone becomes a header with the step on a sheet below it. The asking browser's pages are numbered (step 1 of 3: the email; 2: waiting; 3: continue).

Each request has a four-character reference. The email's subject ends with it (`Sign in to <project> (request AB5F)`), so every email is its own thread rather than one long one, where mail apps fold away the repeated button. The waiting page and the approve page show it too, so someone can match the email to the browser that asked.

## A project's routes

The app's `/login/` route hands its `get` and `post` to Moopa, and `/login/logout/` signs out:

```cfml
<!--- code/apps/hub/routes/login/index.cfc --->
<cfcomponent key="…" open_to="public">
    <cffunction name="get"><cfreturn application.lib.signin.get() /></cffunction>
    <cffunction name="post"><cfreturn application.lib.signin.post() /></cffunction>
</cfcomponent>

<!--- code/apps/hub/routes/login/logout.cfc --->
<cfcomponent key="…" open_to="public">
    <cffunction name="get"><cfset application.lib.signin.logout() /></cffunction>
    <cffunction name="post"><cfset application.lib.signin.logout() /></cffunction>
</cfcomponent>
```

Everything else (the emailed link, the approve page, the waiting page's polling) goes through those two handlers on `/login/`.

## Configuration

| Variable | |
| --- | --- |
| `BASE_URL` | The app's address. The emailed link is built on it, never on the request's `Host` header, which the person asking controls. Required. |
| `SYSADMIN_EMAIL` | The hub's sysadmins. One without a usable hub profile still gets the link; approving it creates their profile, or enables it, so a new project's first sign-in needs no setup. Nothing changes until the link is approved. |
| `TRUSTED_PROXY` | `cloudflare` (or `digitalocean`) when every request reaches the app through that proxy, which then sets the client headers itself. Only then does sign-in use its client address (for the per-IP limit) and, for Cloudflare with visitor location headers on, show roughly where a request came from. Unset: the connection's address and no location, as a client can send any header. |
| Email | Sent with `lib/email.cfc` ([email.md](email.md)). Outside production every message goes to `SYSADMIN_EMAIL`. |
| `APP_ENVIRONMENT=development` | The waiting page also shows the link, so a local stack signs in without email. |

## How it holds up

- **Opening the link changes nothing.** Only the Approve button (a POST) approves, so mail scanners that open links can't sign anyone in.
- **The asking browser is bound to its request** by a secret kept in its session; the emailed link carries a second secret. Only SHA-256 hashes of both are stored.
- **One use, 15 minutes.** A request is approved or turned down once, signs in once, and is over after 15 minutes.
- **Nothing says whether an email has an account.** An unknown address waits like any other; no email is sent. An email that fails to send is logged and looks the same.
- **At most 5 requests per email address and 20 per IP address in 15 minutes.**
- **Signing out ends the 30-day device too.**

A request someone else started still needs the account owner to approve it: the approve page shows the device, roughly where it is (with `TRUSTED_PROXY=cloudflare` and Cloudflare's visitor location headers on) and when it asked, so a request that isn't theirs stands out.

## Inviting someone

System → Profiles → a profile that can sign in → **Invite** gives a message to send: the sign-in address and their email. There is nothing else to share.
