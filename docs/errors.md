# Errors

What Moopa does with an error nothing caught (`application.cfc` `OnError`):

1. **Records it** in `moo_error_log`, with the request's redacted context, shown in **System → Error Log**.
2. **Emails the sysadmin** (`SYSADMIN_EMAIL`) in production, through Moopa's email library or the project's Postmark library ([email.md](email.md)).
3. **Answers the request:** a `req()` call gets JSON with status 500, a page gets the 500 status page.

The project decides who sees the error's details, and may replace the page. Recording and emailing stay Moopa's.

## Who sees the details

The details are the message, the template and line of each frame, and the exception itself. They go in the JSON (`error`, `line`, `exception`) and under the status page's buttons. Everyone else gets a plain message.

`this.moopa_error_details`, set in the project's `Application.cfc` pseudo-constructor, says who sees them in each environment (`APP_ENVIRONMENT`, `production` when unset):

```cfml
<cfset this.moopa_error_details = {
    development: "everyone",
    stage: "sysadmin",
    production: "nobody"
} />
```

| Value | Who sees the details |
|---|---|
| `everyone` | Anyone who hits the error |
| `sysadmin` | A sysadmin signed in to this app |
| `nobody` | No one: read them in System → Error Log |

An environment the setting doesn't name, or no setting at all, is `sysadmin`. Keys match `APP_ENVIRONMENT` without case.

A setting that isn't a struct of those values stops the app starting (`moopa.config.invalidErrorDetails`). If it gets past that, details are shown to no one.

## Replacing the error page

Moopa renders its status pages by tag name, `<cf_moopa_status>`: the 500 page here, and the 403 on Edit profile ([account.md](account.md)). Custom tags are found app first, then shared, then Moopa ([packages.md](packages.md)), so a project's own `moopa_status.cfm` in `code/shared/tags` (or one app's `tags`) replaces Moopa's for those pages.

The project's tag takes the same attributes as Moopa's (`tags/moopa_status.cfm`): `code` (404, 403 or 500), `title`, `message` and `route`. It sets the response status itself. For a 500, its body holds the error's details when they may be shown, and is empty otherwise; render it below the page's own content.

A 500 page may be showing because the database or the session failed, so the tag should read neither.
