# Route access

Every request to a route asks `internal/routing/access_policy.cfc` whether this session may open the endpoint. A route says who it is for with `open_to`, on the component or on one endpoint (the endpoint's wins). With neither, it is `security`.

```cfml
<cfcomponent key="…" open_to="validated">
```

## The levels

| `open_to` | Who opens it |
|---|---|
| `public` | Anyone. |
| `bearer` | A request with `Authorization: Bearer <BEARER_TOKEN>`. Without the token, as `security`. |
| `logged_in` | Anyone logged in with a profile in this app. |
| `validated` | Someone logged in with a profile in this app whom the project's `application.lib.auth.isValidated()` accepts. With [`this.moopa_validated_without_login`](#validated-without-a-login), also a validated session that isn't logged in. |
| `security` | A sysadmin, or a profile or role granted the route in System → Route Access (`moo_route_permission`). |

The checks run in this order, and the first that answers wins:

1. A route's own `checkAccess` endpoint, when it has one, can refuse anyone.
2. `public` opens. `bearer` with the right token opens.
3. `validated`, with `this.moopa_validated_without_login` on, opens to a validated session with a profile in this app.
4. Anyone else must be logged in, with a profile in this app (profiles are app-scoped). If not, the answer is no.
5. A sysadmin opens everything. `logged_in` opens. `validated` opens when `isValidated()` is true.
6. A signed endpoint request (`x-signature`, from `application.lib.auth.signedEndpoint()`) opens.
7. Otherwise `moo_route_permission` decides: a grant to the profile, or to one of its roles, for the route or the endpoint.

## Validated without a login

Some projects verify a visitor (their phone, or their email) to show them a few pages, without giving them a login. Their `application.lib.auth.isValidated()` is true for such a session, which has a profile in `session.auth.profile` but isn't logged in. By default step 4 still turns them away from a `validated` route.

A project like that turns on `this.moopa_validated_without_login` in its `Application.cfc` pseudo-constructor:

```cfml
<cfset this.moopa_validated_without_login = true />
```

Then a `validated` route opens to a session that is not logged in when both hold:

- `application.lib.auth.isValidated()` is true, and
- `session.auth.profile.app_name` is the running app's.

That's all it grants. Such a session still can't open a `logged_in`, `security` or `bearer` route, and isn't a sysadmin. Turn it on only where `isValidated()` is true just for a session the project has verified, and where every `validated` route is safe for someone who has proved who they are but never signed in.

The setting is `true` or `false`; leaving it out is `false`, which is every project's access before it existed. Anything else stops the app starting (`moopa.config.invalidValidatedWithoutLogin`). The app reads it when it starts, so a change takes effect at the next start or [re-initialise](reinitialising.md).

## Checking it

`scripts/test_access_policy.sh` runs the access check on RustCFML against a stub `application.lib.auth`, for each level with the setting off and on, and the setting's validation. No database needed:

```sh
bash scripts/test_access_policy.sh                                            # rustcfml on PATH
RUSTCFML=/path/to/rustcfml bash scripts/test_access_policy.sh
```

Change the access check or the setting, and the harness changes with it.

## Upgrading

Nothing to do. A project that doesn't set `this.moopa_validated_without_login` keeps its route access exactly as it was.
