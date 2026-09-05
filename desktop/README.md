# iMail Desktop

Native desktop iMail for Windows, built with C#/.NET and Avalonia.

## Architecture

`iMail Desktop -> HTTPS + WSS -> Mailbox-DNS API -> hosted mailbox / connected external mailbox`

The desktop client never needs raw browser-style IMAP/SMTP access for normal use. Hosted Ithute accounts and previously verified connected accounts use the same login. A first-time external mailbox can be registered from the desktop setup screen with secure IMAP/SMTP settings; Mailbox-DNS verifies and remembers the working server profile, not the mailbox password.

Production API base URL: `https://api.ithute.co.ls/api/v1`

## Implemented desktop features

- provider-neutral iMail login and branding
- normal login for hosted and previously verified connected accounts
- first-time external mailbox setup with secure standard-domain fallbacks and manual IMAP/SMTP fields
- folder navigation and exact folder counts
- inbox/message list and search
- message reader
- automatic read marking
- star/unstar, mark unread, archive, delete/trash
- compose, To/Cc/Bcc, attachments and send
- reply and forward
- draft save
- account identity view and sign out
- realtime Mailbox-DNS WebSocket refresh with reconnect
- responsive 3-pane desktop layout; folder rail collapses on narrower PC windows
- self-contained Windows publish script
- optional Inno Setup installer definition

The desktop client intentionally does **not** persist mailbox passwords.

## Requirements for development

- .NET 8 SDK or newer
- Windows 10/11 for the Windows target
- optional: Inno Setup 6 if you want a `Setup.exe`

Avalonia is pinned to `12.1.2`.

## Run from source

```powershell
cd desktop\IMail.Desktop
dotnet restore
dotnet run
```

## Build a Windows application

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\desktop\build-windows.ps1
```

The self-contained build is written to:

```text
desktop\artifacts\win-x64\
```

If `iscc.exe` is available on `PATH`, the same script also creates an installer under:

```text
desktop\artifacts\installer\
```

## API endpoints used

Hosted sessions use `/webmail/*`; connected sessions use `/webmail/external/*`. The client uses the existing API for session login, folders, counts, messages, message detail, flags, move, delete, drafts, identity, sending and attachments. Realtime updates use the corresponding `/events/ws` WebSocket endpoint.

## Security

- HTTPS/WSS only in production
- server-side connected-mail profile verification
- password supplied only for authentication/setup and not written to desktop configuration
- connected-mail network/TLS/SSRF protections remain enforced by Mailbox-DNS
- Windows executable runs as the current user and does not request administrator privileges
