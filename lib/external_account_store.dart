import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

class ExternalAccountStore {
  ExternalAccountStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'imail.external.accounts.v1';

  final FlutterSecureStorage _storage;

  Future<List<MailAccount>> loadAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final accounts = <MailAccount>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          accounts.add(
            MailAccount.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Ignore a single corrupt entry rather than hiding all accounts.
        }
      }
      return accounts;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAccount(MailAccount account) async {
    final accounts = [...await loadAccounts()];
    final index = accounts.indexWhere(
      (item) => item.email.toLowerCase() == account.email.toLowerCase(),
    );
    if (index < 0) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }
    await _write(accounts);

    // The account has already passed iMail's IMAP + SMTP verification. Give
    // Mailbox-DNS those exact verified settings so it can remember the mailbox
    // as a known account. The server independently verifies the exact endpoints
    // once, but does not repeat discovery/candidate probing.
    await syncKnownAccount(account);
  }

  Future<bool> syncKnownAccount(MailAccount account) async {
    final authentication = account.incoming.authentication;
    if (authentication is! PlainAuthentication) {
      // OAuth and other future authentication types need their own server-side
      // token flow. Do not try to turn them into password authentication.
      return false;
    }

    final incoming = account.incoming.serverConfig;
    final outgoing = account.outgoing.serverConfig;
    try {
      await IMailApiClient()
          .registerExternalAccount(
            address: account.email,
            password: authentication.password,
            username: authentication.userName,
            displayName: account.userName,
            imapHost: incoming.hostname,
            imapPort: incoming.port,
            imapSecurity: _securityName(incoming.socketType),
            smtpHost: outgoing.hostname,
            smtpPort: outgoing.port,
            smtpSecurity: _securityName(outgoing.socketType),
          )
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (_) {
      // Local secure storage remains authoritative for the device. A temporary
      // API outage must not make a mailbox that already passed direct IMAP/SMTP
      // verification unusable. syncKnownAccounts() retries later.
      return false;
    }
  }

  Future<void> syncKnownAccounts([List<MailAccount>? supplied]) async {
    final accounts = supplied ?? await loadAccounts();
    for (final account in accounts) {
      await syncKnownAccount(account);
    }
  }

  Future<void> removeAccount(String email) async {
    final accounts = [...await loadAccounts()]
      ..removeWhere((item) => item.email.toLowerCase() == email.toLowerCase());
    await _write(accounts);
  }

  String _securityName(SocketType value) =>
      value == SocketType.ssl ? 'ssl' : 'starttls';

  Future<void> _write(List<MailAccount> accounts) async {
    // MailAccount contains the authenticated server configuration. This JSON is
    // intentionally stored only in platform secure storage, never plain prefs.
    final encoded = jsonEncode(accounts.map((item) => item.toJson()).toList());
    await _storage.write(key: _accountsKey, value: encoded);
  }
}
