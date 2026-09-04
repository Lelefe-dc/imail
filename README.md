# iMail — Ithute Mail mobile app

iMail is a standalone Flutter email client for mailboxes hosted by the Mailbox-DNS / Ithute Mail platform. The app does not create mailboxes and does not contain Mailbox-DNS backend code. It consumes the production Mailbox-DNS webmail API over HTTPS.

## Production API

The app connects by default to:

```text
https://api.ithute.co.ls/api/v1
```

Mailbox users sign in with the email address and mailbox password already configured in Mailbox-DNS. After authentication, iMail loads the real server-side folders, unread counts and messages for that mailbox.

## Current mobile features

- Existing-mailbox login through `/api/v1/webmail/session`
- Secure server session storage; mailbox passwords are not persisted on the device
- Session restore on relaunch
- Real IMAP folders and folder counts
- Inbox/folder navigation and server-side search
- Read, unread, star, move and delete actions
- Compose, reply, forward and save draft operations
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

Production Android traffic is HTTPS-only (`usesCleartextTraffic=false`). Before Play Store publishing, configure the private upload signing key and complete store metadata, privacy/data-safety declarations, screenshots, final versioning and release validation.
