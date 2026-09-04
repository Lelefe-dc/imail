# iMail — Ithute Mail mobile app

iMail is a standalone Flutter email client for Ithute-hosted mailboxes and standard IMAP/SMTP mail servers.

## Production API

The hosted Ithute account flow connects by default to:

```text
https://api.ithute.co.ls/api/v1
```

Mailbox users sign in with the email address and mailbox password already configured in Mailbox-DNS.

## Connected mail accounts

A new external mailbox is configured once. iMail verifies incoming IMAP and outgoing SMTP separately, stores the verified account configuration in platform secure storage, and registers the verified server settings with Mailbox-DNS. Mailbox-DNS independently verifies those exact endpoints and remembers the account configuration without permanently storing the mailbox password.

After that first setup, the account uses the normal iMail sign-in screen. Mailbox-DNS looks up the remembered server configuration and performs one direct authentication instead of repeating hostname, port and TLS discovery.

The setup supports:

- secure automatic discovery
- manual IMAP and SMTP host, port and SSL/TLS or STARTTLS settings
- separate login username when required
- verification of incoming and outgoing authentication before saving
- multiple connected accounts in platform secure storage
- provider-neutral standard domain defaults

## Realtime mail

Hosted and remembered connected accounts use Mailbox-DNS HTTPS APIs for mailbox operations. While iMail is active it also maintains the authenticated Mailbox-DNS WebSocket for fast mailbox-change events. Periodic HTTP synchronization remains as a fallback if the socket is unavailable.

The active-app realtime path can play an iMail alert and refresh the mailbox immediately when a change is reported. Fully closed-device wake-up notifications require the separate background push transport; the foreground WebSocket is not presented as a replacement for operating-system push delivery.

## Current mobile features

- normal sign-in for Ithute and previously verified connected accounts
- one-time external IMAP/SMTP discovery and verification
- secure session and account configuration storage
- realtime Mailbox-DNS WebSocket with HTTP fallback
- bounded offline cache for recent mail
- real folders, counts, search and pagination
- conversation grouping for loaded related messages
- long-press multi-select and bulk actions
- configurable left/right swipe actions
- read, unread, star, move, archive and delete
- compose, reply, reply-all, forward and attachments
- account switcher and first-time account connection
- conversation, notification, swipe, density and offline-cache settings
- Ithute/iMail-only customer-facing branding

## Run

```bash
flutter pub get
flutter run
```

For controlled staging/testing only, the endpoint can be overridden at build time:

```bash
flutter run --dart-define=IMAIL_API_BASE_URL=https://staging.example.com/api/v1
```

## Android

Application ID:

```text
ls.co.ithute.imail
```

The repository pins Android Gradle Plugin 8.11.1, Kotlin 2.2.20 and Gradle 8.14.3. Production Android traffic is HTTPS-only.
