# Authentication email setup

`zen-identity` verifies signup-confirmation and password-recovery links on the application server.
The reference Go templates are [confirmation.html](../server/zen-identity/src/main/resources/email-templates/confirmation.html)
and [recovery.html](../server/zen-identity/src/main/resources/email-templates/recovery.html). Copy
each into the matching Supabase Auth email template before enabling the flow.

## Configure the hosted Supabase project

1. Set the project's **Site URL** to the public application origin (scheme and host only, with no
   path or trailing slash) that should appear in both the email link and its visible text. The
   templates use `{{ .SiteURL }}` for the link to `/auth/confirm`; a wrong Site URL makes every new
   link point to the wrong host.
2. Configure an authenticated SMTP sender for the application's domain and use a transactional
   relay that does not rewrite authentication links. The sending domain, SPF/DKIM/DMARC, branding,
   and relay are application-operator choices.
3. Install the `confirmation.html` template for **Confirm signup** and `recovery.html` for
   **Reset password**. GoTrue sends one template for each type, and the signup and recovery calls
   carry no language. An application supporting multiple locales must put its language variants
   in the same template body.
4. Deploy the application with `/auth/confirm`, `/auth/callback`, and
   `POST /api/v1/auth/confirm` available **before** activating templates that point to them.
5. Hosted Supabase projects do not read this repository's `supabase/config.toml`. Apply the Site
   URL, SMTP sender, and templates to the hosted project in its dashboard or through the
   Supabase Management API. jZen does not check that those project settings match the deployed
   application.

The template uses the app-owned Site URL for the initial link and GoTrue's `{{ .RedirectTo }}` for
the final hand-off. jZen validates that return address against `auth.redirect-uri` and
`auth.redirect-uris` by exact match before sending the email. A native app's URI must be in
`AUTH_REDIRECT_URIS` and in the Supabase project's Redirect URLs. A refused URI sends no email and
is not echoed in the response.

The Continue page is a GET and does not verify or spend the token hash. The application receives
the hash only after the person continues, then posts it once to `/api/v1/auth/confirm`. A timeout
may leave the verification outcome unknown; the one-time hash is never retried.

The old `/auth/callback` fragment exchange remains available for emails already sent with
`{{ .ConfirmationURL }}`. Such a link keeps its original expiry; once those links can no longer be
used, operators may replace the old template without affecting the new flow.
