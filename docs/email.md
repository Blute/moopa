# Email

`application.lib.email` (`lib/email.cfc`) sends transactional email through [Cloudflare Email Sending](https://developers.cloudflare.com/email-service/)'s REST API. It is plain HTTPS, so it works from any host, not only Workers.

## Configuration

| Variable | |
|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | The Cloudflare account that owns the sending domain. |
| `CLOUDFLARE_EMAIL_TOKEN` | An API token with the **Email Sending Write** permission. |
| `EMAIL_FROM` | Default From address. Its domain must be onboarded to Email Sending (the onboarding adds its bounce MX, SPF, DKIM and DMARC records). |
| `EMAIL_FROM_NAME` | Optional display name. Without it the project title is used. |
| `SYSADMIN_EMAIL` | Where every message goes outside production (comma-separated). |

`isConfigured()` is true when the first three are set. Email Sending needs the account's Workers Paid plan; 3,000 messages a month are included.

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
    <!--- result.status is the HTTP status; result.errors holds Cloudflare's { code, message } entries --->
</cfif>
```

- `text` is optional: without it a plain-text part is derived from the HTML.
- `layout(content, footer)` wraps a body in a plain, widely supported email layout. The footer is optional HTML.
- `attachment(filename, bytes, type = "application/pdf")` builds one attachment entry.
- `result.delivered`, `result.queued` and `result.bounced` list recipients as Cloudflare reports them.
- Limits: 50 recipients across to, cc and bcc; 5 MiB per message including attachments.

## Framework email

Moopa's own messages (the production 500-error email) go through `application.lib.core.sendFrameworkEmail()`: this library when it is configured, otherwise the project's own `lib/postmark.cfc` if it has one, otherwise nothing. A project can move to Cloudflare by setting the variables above; until then nothing changes.
