import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

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

    // Best-effort registration with Mailbox-DNS. The local account remains
    // usable even if the API is temporarily unavailable, and reconnect can
    // repair the server-side known-account profile later from these exact
    // already-verified settings.
    await syncKnownAccount(account);
  }

  Future<bool> syncKnownAccount(MailAccount account) async {
    final incomingAuthentication = account.incoming.authentication;
    if (incomingAuthentication is! PlainAuthentication) {
      // OAuth and other future authentication types need their own server-side
      // token flow. Do not try to turn them into password authentication.
      return false;
    }

    final incoming = account.incoming.serverConfig;
    final outgoing = account.outgoing.serverConfig;

    // First use the lightweight registration endpoint when available.
    try {
      await IMailApiClient()
          .registerExternalAccount(
            address: account.email,
            password: incomingAuthentication.password,
            username: incomingAuthentication.userName,
            displayName: account.userName,
            imapHost: incoming.hostname,
            imapPort: incoming.port,
            imapSecurity: _securityName(incoming.socketType),
            smtpHost: outgoing.hostname,
            smtpPort: outgoing.port,
            smtpSecurity: _securityName(outgoing.socketType),
          )
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      // Older/stale deployments may not expose register-known yet, or a known
      // profile may need to be repaired. Fall through to the normal external
      // session endpoint with the exact settings that already worked on-device.
    }

    return _repairKnownAccountViaExactSession(
      account,
      incomingAuthentication,
    );
  }

  Future<bool> _repairKnownAccountViaExactSession(
    MailAccount account,
    PlainAuthentication authentication,
  ) async {
    final incoming = account.incoming.serverConfig;
    final outgoing = account.outgoing.serverConfig;
    final api = IMailApiClient();
    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('${api.baseUrl}/webmail/external/session'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'address': account.email.trim().toLowerCase(),
              'password': authentication.password,
              'username': authentication.userName.trim().isEmpty
                  ? account.email.trim().toLowerCase()
                  : authentication.userName.trim(),
              'display_name': account.userName.trim(),
              'imap_host': incoming.hostname,
              'imap_port': incoming.port,
              'imap_security': _securityName(incoming.socketType),
              'smtp_host': outgoing.hostname,
              'smtp_port': outgoing.port,
              'smtp_security': _securityName(outgoing.socketType),
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      // The successful exact-session call repairs/persists the known profile.
      // We only needed that side effect here, so close the temporary API
      // session immediately rather than leaving an unused server session alive.
      final rawCookie = response.headers['set-cookie'];
      if (rawCookie != null && rawCookie.isNotEmpty) {
        final cookie = rawCookie.split(';').first.trim();
        try {
          await client
              .delete(
                Uri.parse('${api.baseUrl}/webmail/external/session'),
                headers: {'Accept': 'application/json', 'Cookie': cookie},
              )
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
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
