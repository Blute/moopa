# Account pages

Moopa serves two pages for the signed-in person, linked from the profile menu (in Hub, which serves Moopa's own pages):

| Page | Route | What it does |
|---|---|---|
| Edit profile | `/account/profile` (`routes/account/profile.cfc`) | The person's name, preferred name and picture. Email, roles and sign-in stay in System › Profiles, because email is how a person signs in. |
| Sign-in activity | `/account/signins` (`routes/account/signins.cfc`) | Signed-in devices, with sign-out, and the last 90 days of sign-ins ([signin.md](signin.md)). |

Both are open to anyone signed in, for their own profile. A sysadmin can open anyone's with `?profile=<id>`. On Edit profile, anyone else asking for another profile is refused, with a 403 for the page and a refusal for its endpoints. A picture can only be saved by the person who uploaded it.

## Replacing one in a project

A project's route wins over Moopa's at the same URL. Package precedence is app over shared over Moopa (`application.cfc` `_packagePrecedence`), so a project replaces Edit profile with its own `code/apps/hub/routes/account/profile.cfc` (or `code/shared/routes/account/profile.cfc`). The route needs its own `key`, and the project's `route_links.json` lists it. The profile menu still links to `/account/profile`, so the project's page is the one people get. Only `/sysadmin` is reserved: Moopa refuses to start if a project has a route there.
