import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  }

  Future<void> removeAccount(String email) async {
    final accounts = [...await loadAccounts()]
      ..removeWhere((item) => item.email.toLowerCase() == email.toLowerCase());
    await _write(accounts);
  }

  Future<void> _write(List<MailAccount> accounts) async {
    // MailAccount contains the authenticated server configuration. This JSON is
    // intentionally stored only in platform secure storage, never plain prefs.
    final encoded = jsonEncode(accounts.map((item) => item.toJson()).toList());
    await _storage.write(key: _accountsKey, value: encoded);
  }
}
