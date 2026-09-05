# iMail — Ithute Mail apps

iMail now contains both the Flutter mobile client and the native C#/.NET Avalonia desktop client for Ithute-hosted mailboxes and standard connected mail servers.

## Production API

The applications connect by default to:

```text
https://api.ithute.co.ls/api/v1
```

Mailbox users sign in with the email address and mailbox password already configured in Mailbox-DNS.

## Connected mail accounts

A new external mailbox is configured once. iMail verifies incoming IMAP and outgoing SMTP separately and registers the verified server settings with Mailbox-DNS. Mailbox-DNS independently verifies the endpoints and remembers the account configuration without permanently storing the mailbox password.

After that first setup, the account uses the normal iMail sign-in screen. Mailbox-DNS looks up the remembered server configuration and performs one direct authentication instead of repeating hostname, port and TLS discovery.

The setup supports:

- secure automatic/standard-domain discovery paths
- manual IMAP and SMTP host, port and SSL/TLS or STARTTLS settings
- separate login username when required
- verification of incoming and outgoing authentication before registration
- provider-neutral standard domain defaults

## Realtime mail

Hosted and remembered connected accounts use Mailbox-DNS HTTPS APIs for mailbox operations. Active clients maintain the authenticated Mailbox-DNS WebSocket for fast mailbox-change events, with HTTP refresh as the data source.

The mobile active-app realtime path can play an iMail alert and refresh the mailbox immediately when a change is reported. Fully closed-device wake-up notifications require the separate background push transport; the foreground WebSocket is not presented as a replacement for operating-system push delivery.

## Flutter mobile app

Current mobile features include:

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

Run mobile:

```bash
flutter pub get
flutter run
```

For controlled staging/testing only, the endpoint can be overridden at build time:

```bash
flutter run --dart-define=IMAIL_API_BASE_URL=https://staging.example.com/api/v1
```

### Android

Application ID:

```text
ls.co.ithute.imail
```

The repository pins Android Gradle Plugin 8.11.1, Kotlin 2.2.20 and Gradle 8.14.3. Production Android traffic is HTTPS-only.

## Windows desktop app — C# + .NET + Avalonia

The native desktop application lives in:

```text
desktop/IMail.Desktop
```

It provides a responsive three-pane desktop mailbox, hosted/known-connected account sign-in, first-time connected mailbox setup, folders/counts, search, message reading, realtime WebSocket refresh, star/read/archive/delete actions, compose/reply/forward, To/Cc/Bcc, attachments, drafts, identity and sign-out.

The desktop project targets .NET 8 and Avalonia 12.1.2. It is published as a self-contained Windows application, so end users do not need to install .NET separately.

Run from source:

```powershell
cd desktop\IMail.Desktop
dotnet restore
dotnet run
```

Build Windows x64:

```powershell
powershell -ExecutionPolicy Bypass -File .\desktop\build-windows.ps1
```

The publish output is written to `desktop\artifacts\win-x64`. If Inno Setup is installed, the same script also creates an iMail Windows installer. See `desktop/README.md` for the desktop architecture and packaging details.
