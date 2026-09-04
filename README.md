# iMail — Ithute Mail mobile app

iMail is a standalone Flutter email client for mailboxes hosted by the Mailbox-DNS / Ithute Mail platform. The app does not create mailboxes and does not contain Mailbox-DNS backend code. It consumes the production Mailbox-DNS webmail API over HTTPS.

## Production API

The app connects by default to:

```text
https://api.ithute.co.ls/api/v1
```

Mailbox users sign in with the email address and mailbox password already configured in Mailbox-DNS. After authentication, iMail loads the real server-side folders, unread counts and messages for that mailbox.

## Mail event architecture

Mailbox reads and mutations are serialized through an event BLoC. Foreground mailbox listeners reconcile folder counts and selected-folder messages automatically, app resume triggers an immediate sync, and optimistic mutations update the UI before the server round trip then roll back on failure.

Folder counters keep both total and unread values. Inbox/spam/category-style folders display unread counts; Sent, Drafts, Trash and similar folders display real message totals.

The foreground listener checks production Mailbox-DNS every 12 seconds by default and pauses when the app is backgrounded. For controlled tuning use `--dart-define=IMAIL_MAIL_POLL_SECONDS=<seconds>` (minimum 5 seconds). No local backend is required.

## Current mobile features

- Existing-mailbox login through `/api/v1/webmail/session`
- Secure server session storage; mailbox passwords are not persisted on the device
- Fast cached-account startup and session restore
- Real IMAP folders with separate total/unread counts
- Foreground incoming-mail/count listener and resume reconciliation
- Inbox/folder navigation and server-side search
- Read, unread, star, move, archive and delete actions with optimistic mutation handling
- Compose, reply, reply-all, forward, attachments and save-draft operations
- Clean Ithute iMail branded Material 3 UI

## Run against production

```bash
flutter pub get
flutter run
```

No local Mailbox-DNS backend is required. The default API endpoint is already the production Ithute Mail API.

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
