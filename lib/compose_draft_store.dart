import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ComposeDraftSnapshot {
  const ComposeDraftSnapshot({
    this.to = '',
    this.cc = '',
    this.bcc = '',
    this.subject = '',
    this.body = '',
  });

  final String to;
  final String cc;
  final String bcc;
  final String subject;
  final String body;

  bool get isEmpty =>
      to.trim().isEmpty &&
      cc.trim().isEmpty &&
      bcc.trim().isEmpty &&
      subject.trim().isEmpty &&
      body.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'to': to,
        'cc': cc,
        'bcc': bcc,
        'subject': subject,
        'body': body,
      };

  factory ComposeDraftSnapshot.fromJson(Map<String, dynamic> json) =>
      ComposeDraftSnapshot(
        to: json['to']?.toString() ?? '',
        cc: json['cc']?.toString() ?? '',
        bcc: json['bcc']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
      );
}

class ComposeDraftStore {
  ComposeDraftStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String account, String draftId) =>
      'imail.compose.${account.trim().toLowerCase()}.${draftId.trim().toLowerCase()}';

  Future<ComposeDraftSnapshot?> load(String account, String draftId) async {
    final raw = await _storage.read(key: _key(account, draftId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ComposeDraftSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String account,
    String draftId,
    ComposeDraftSnapshot snapshot,
  ) async {
    if (snapshot.isEmpty) {
      await clear(account, draftId);
      return;
    }
    await _storage.write(
      key: _key(account, draftId),
      value: jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> clear(String account, String draftId) =>
      _storage.delete(key: _key(account, draftId));
}
