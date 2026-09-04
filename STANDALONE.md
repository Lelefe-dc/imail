# iMail standalone architecture

`iMail` is an independent Flutter mobile client. It must not contain Mailbox-DNS backend code, database migrations, Postfix/Dovecot configuration or control-panel code.

Production flow:

```text
iMail Flutter app
    -> HTTPS
https://api.ithute.co.ls/api/v1
    -> Mailbox-DNS webmail API
    -> IMAP / SMTP mail services
```

Mailbox provisioning remains in Mailbox-DNS. iMail only signs existing mailbox users in and consumes their server-side mail data.

The mobile client uses an event BLoC to serialize mailbox commands and mutations, foreground polling to listen for mailbox changes while no server push stream is available, lifecycle-aware resume synchronization, optimistic UI mutation with rollback, and a cached account shell for fast startup.
