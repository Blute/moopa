# Email

`application.lib.email` (`lib/email.cfc`) sends transactional email through [Cloudflare Email Sending](https://developers.cloudflare.com/email-service/)'s REST API, or through [Postmark](https://postmarkapp.com/developer/api/email-api)'s when `EMAIL_TRANSPORT` is `postmark`. Both are plain HTTPS, so they work from any host. Everything Moopa sends (the sign-in link, the production 500-error email) and everything a project sends with `send()` goes the same way.

## Configuration

| Variable | |
|---|---|
| `EMAIL_TRANSPORT` | `cloudflare` (the default) or `postmark`. Any other value stops the application starting. |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare: the account that owns the sending domain. |
| `CLOUDFLARE_EMAIL_TOKEN` | Cloudflare: an API token with the **Email Sending Write** permission. |
| `POSTMARK_SERVER_TOKEN` | Postmark: the sending server's API token. |
| `POSTMARK_MESSAGE_STREAM` | Postmark: the message stream. `outbound` when not set. |
| `EMAIL_FROM` | Default From address. Cloudflare: its domain must be onboarded to Email Sending (the onboarding adds its bounce MX, SPF, DKIM and DMARC records). Postmark: a sender signature or an address on a verified domain. |
| `EMAIL_FROM_NAME` | Optional display name. Without it the project title is used. |
| `SYSADMIN_EMAIL` | Where every message goes outside production (comma-separated). |

`isConfigured()` is true when `EMAIL_FROM` and the chosen transport's variables are set: the two `CLOUDFLARE_*` ones, or `POSTMARK_SERVER_TOKEN`. Email Sending needs the account's Workers Paid plan; 3,000 messages a month are included.

## Outside production

When `APP_ENVIRONMENT` is not `production`, a message goes only to `SYSADMIN_EMAIL`: its own to, cc and bcc are dropped, and the sender's display name names the environment (`Hub (staging)`), so a copy is never mistaken for the real one. `SYSADMIN_EMAIL` must be set, or `send()` throws. The result says what really happened: `to`, `cc` and `redirected`.

## Sending

```cfml
<cfset mail = application.lib.email />
<cfset result = mail.send(
    to = "a@example.com, b@example.com",
    cc = "",
    subject = "Your report",
    html = mail.layout("<h1>Good morning</h1><p>Your report is attached.</p>", "<p>Example Pty Ltd</p>"),
    attachments = [ mail.attachment("report.pdf", pdfBytes) ]
) />
<cfif NOT result.success>
    <!--- result.status is the HTTP status; result.errors holds the service's { code, message } entries --->
</cfif>
```

- `text` is optional: without it a plain-text part is derived from the HTML.
- `layout(content, footer)` wraps a body in a plain, widely supported email layout. The footer is optional HTML.
- `attachment(filename, bytes, type = "application/pdf")` builds one attachment entry.
- `result.delivered`, `result.queued` and `result.bounced` list recipients as Cloudflare reports them. Postmark answers only that it accepted the message, so every recipient is in `result.queued`; `result.errors` holds its `{ code, message }` when it refused.
- Limits: 50 recipients across to, cc and bcc; 5 MiB per message including attachments.

## Framework email

Moopa's own messages (the production 500-error email) go through `application.lib.core.sendFrameworkEmail()`: this library when it is configured, otherwise the project's own `lib/postmark.cfc` if it has one, otherwise nothing. A project can move to Cloudflare by setting the variables above; until then nothing changes.
