import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class MailCache {
  MailCache({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String address, String folder) =>
      'imail.cache.${address.trim().toLowerCase()}.${folder.trim().toLowerCase()}';

  Future<List<MailMessage>> load(String address, String folder) async {
    if (address.trim().isEmpty || folder.trim().isEmpty) return const [];
    final raw = await _storage.read(key: _key(address, folder));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => MailMessage.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.uid.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(
    String address,
    String folder,
    List<MailMessage> messages,
  ) async {
    if (address.trim().isEmpty || folder.trim().isEmpty) return;
    final rows = messages.take(100).map(_messageJson).toList(growable: false);
    await _storage.write(
      key: _key(address, folder),
      value: jsonEncode(rows),
    );
  }

  Future<void> clear(String address, String folder) =>
      _storage.delete(key: _key(address, folder));

  Future<void> clearAccount(String address, Iterable<String> folders) async {
    for (final folder in folders) {
      await clear(address, folder);
    }
  }

  Map<String, dynamic> _messageJson(MailMessage item) => {
        'uid': item.uid,
        'from': item.from,
        'to': item.to,
        'cc': item.cc,
        'reply_to': item.replyTo,
        'subject': item.subject,
        'date': item.date,
        'snippet': item.snippet,
        'seen': item.seen,
        'flagged': item.flagged,
        'answered': item.answered,
        'draft': item.draft,
        'body_text': item.bodyText,
        'message_id': item.messageId,
        'in_reply_to': item.inReplyTo,
        'references': item.references,
        'attachments': item.attachments
            .map(
              (attachment) => {
                'index': attachment.index,
                'filename': attachment.filename,
                'content_type': attachment.contentType,
                'size': attachment.size,
              },
            )
            .toList(growable: false),
      };
}
