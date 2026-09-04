# iMail — Ithute Mail mobile app

A production-oriented Flutter client for the existing `Mailbox-DNS` webmail API. The visual direction combines the clean Gmail-style interaction patterns from the two supplied Flutter examples with Ithute iMail branding.

## What works

- Login with a mailbox already configured on the Mailbox-DNS platform.
- Securely stores only the server-issued webmail session cookie; the mailbox password is not saved by the app.
- Restores an active session on relaunch.
- Loads real IMAP folders, folder counts and messages from `/api/v1/webmail`.
- Inbox/folder navigation, pull-to-refresh and server-side search.
- Open messages, mark unread, star/unstar, move and delete.
- Compose, reply, forward and save drafts through the existing backend.
- Branded login/splash/inbox UI and Android launcher vector.

## Run

```bash
flutter pub get
flutter run --dart-define=IMAIL_API_BASE_URL=https://panel.ithute.co.ls/api/v1
```

The API URL defaults to `https://panel.ithute.co.ls/api/v1`, so the `--dart-define` is only needed for local/staging environments.

For local Android emulator testing against a development backend, use your reachable host URL (for example `http://10.0.2.2:8000/api/v1`) and temporarily allow cleartext traffic only in a debug manifest/network config. Production remains HTTPS-only.

## Play Store readiness still required before release

Use a private upload keystore and replace the temporary debug release signing configuration. Then add final store screenshots, privacy policy/data-safety declarations, versioning, crash reporting and push notifications when the platform notification service is ready.
# imail
