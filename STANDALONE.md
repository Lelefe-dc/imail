# Standalone architecture

iMail is intentionally maintained as an independent Flutter application. Mailbox-DNS is the mail platform and remains the source of truth for mailbox accounts and email data.

## Runtime relationship

```text
iMail Flutter app
      |
      | HTTPS REST API
      v
https://api.ithute.co.ls/api/v1/webmail
      |
      v
Mailbox-DNS / IMAP / SMTP
```

The app contains no Mailbox-DNS database, migrations, Postfix/Dovecot configuration, domain-management logic or mailbox registration flow.

A mailbox is created/configured in Mailbox-DNS first. iMail then authenticates that existing mailbox through the production webmail API and displays the mailbox data returned by the platform.
