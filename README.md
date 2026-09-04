# iMail — Ithute Mail mobile app

iMail is a standalone Flutter email client. Ithute-hosted mailboxes use the Mailbox-DNS / Ithute Mail production API, while external providers can connect directly with standard IMAP + SMTP settings.

## Ithute Mail production API

The hosted Ithute account flow connects by default to:

```text
https://api.ithute.co.ls/api/v1
```

Mailbox users sign in with the email address and mailbox password already configured in Mailbox-DNS. After authentication, iMail loads the real server-side folders, unread counts and messages for that mailbox.

## External email providers

iMail can also connect directly to standard mail providers such as Zeecom, cPanel/Plesk hosted mail, and other IMAP + SMTP servers.

From the sign-in screen choose **Other email account**. The account setup supports:

- secure automatic server discovery from the email address
- manual IMAP hostname, port and SSL/TLS or STARTTLS settings
- manual SMTP hostname, port and SSL/TLS or STARTTLS settings
- separate login username when required by the provider
- connection testing before the account is saved
- multiple external accounts stored in Android/iOS secure storage
- remote folders, inbox reading, search, star/read state, compose, reply, reply-all, forward and attachments
- foreground incoming-mail polling while an external mailbox is open

For common Zeecom/cPanel mailboxes the setup screen includes a preset that uses the full email address as username, `mail.<domain>` for incoming/outgoing hosts, IMAP 993 over SSL and SMTP 465 over SSL. If a provider publishes different values, use Manual setup and enter those exact values.

External account credentials are not sent to Mailbox-DNS. They are kept in platform secure storage on the device and used by iMail to authenticate directly to the configured IMAP/SMTP server.

## Mail event architecture

Mailbox-DNS reads and mutations are serialized through an event BLoC. Foreground mailbox listeners reconcile folder counts and selected-folder messages automatically, app resume triggers an immediate sync, and optimistic mutations update the UI before the server round trip then roll back on failure.

Folder counters keep both total and unread values. Inbox/spam/category-style folders display unread counts; Sent, Drafts, Trash and similar folders display real message totals.

The Ithute foreground listener checks production Mailbox-DNS every 12 seconds by default and pauses when the app is backgrounded. External IMAP accounts use the mail client's incoming-event polling while their mailbox screen is active.

## Current mobile features

- Existing Ithute mailbox login through `/api/v1/webmail/session`
- Standard external IMAP + SMTP account configuration
- Secure session / external credential storage
- Fast cached-account startup and session restore
- Real folders and messages
- Foreground incoming-mail listeners
- Inbox/folder navigation and search
- Read, unread, star, move, archive and delete actions
- Compose, reply, reply-all, forward and attachments
- Clean Ithute iMail branded Material 3 UI

## Run

```bash
flutter pub get
flutter run
```

No local Mailbox-DNS backend is required for the Ithute production account flow. The default API endpoint is already the production Ithute Mail API.

For controlled staging/testing only, the endpoint can still be overridden at build time without editing source:

```bash
flutter run --dart-define=IMAIL_API_BASE_URL=https://staging.example.com/api/v1
```

## Android

Application ID:

```text
ls.co.ithute.imail
```

Production Android traffic is HTTPS-only (`usesCleartextTraffic=false`). The native launch theme uses the iMail surface and launcher mark so startup does not sit on a plain white window before Flutter paints.
