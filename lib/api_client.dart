import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class IMailApiClient {
  IMailApiClient({
    String? baseUrl,
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : baseUrl = (baseUrl ?? const String.fromEnvironment(
          'IMAIL_API_BASE_URL',
          defaultValue: 'https://api.ithute.co.ls/api/v1',
        ))
            .replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final String baseUrl;
  final http.Client _client;
  final FlutterSecureStorage _storage;

  String? _cookie;
  String? _cachedAddress;

  static const _cookieStorageKey = 'imail_webmail_session_cookie';
  static const _addressStorageKey = 'imail_webmail_address';

  String? get cachedAddress => _cachedAddress;

  Future<bool> restoreCookie() async {
    final values = await Future.wait<String?>([
      _storage.read(key: _cookieStorageKey),
      _storage.read(key: _addressStorageKey),
    ]);
    _cookie = values[0];
    _cachedAddress = values[1];
    return _cookie != null && _cookie!.isNotEmpty;
  }

  Future<void> clearLocalSession() async {
    _cookie = null;
    _cachedAddress = null;
    await Future.wait<void>([
      _storage.delete(key: _cookieStorageKey),
      _storage.delete(key: _addressStorageKey),
    ]);
  }

  Map<String, String> _headers({bool jsonBody = false}) => {
        'Accept': 'application/json',
        if (jsonBody) 'Content-Type': 'application/json',
        if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
      };

  Uri _uri(String path, [Map<String, String?>? query]) {
    final values = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) values[key] = value;
    });
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: values.isEmpty ? null : values,
    );
  }

  dynamic _decode(http.Response response, {bool allowEmpty = false}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (allowEmpty && response.body.trim().isEmpty) return null;
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    }

    String message = 'Request failed (${response.statusCode})';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {}
    throw ApiException(message, statusCode: response.statusCode);
  }

  void _checkBinary(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'Request failed (${response.statusCode})';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {}
    throw ApiException(message, statusCode: response.statusCode);
  }

  Future<String> login(String address, String password) async {
    final normalized = address.trim().toLowerCase();
    final response = await _client.post(
      _uri('/webmail/session'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'address': normalized, 'password': password}),
    );
    final decoded = Map<String, dynamic>.from(_decode(response));
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) {
      throw ApiException(
        'The server authenticated the mailbox but did not return a session cookie.',
      );
    }

    _cookie = rawSetCookie.split(';').first.trim();
    _cachedAddress = decoded['address']?.toString() ?? normalized;
    await Future.wait<void>([
      _storage.write(key: _cookieStorageKey, value: _cookie),
      _storage.write(key: _addressStorageKey, value: _cachedAddress),
    ]);
    return _cachedAddress!;
  }

  Future<String> sessionAddress() async {
    final response = await _client.get(
      _uri('/webmail/session'),
      headers: _headers(),
    );
    final decoded = Map<String, dynamic>.from(_decode(response));
    final value = decoded['address']?.toString() ?? '';
    if (value.isNotEmpty && value != _cachedAddress) {
      _cachedAddress = value;
      await _storage.write(key: _addressStorageKey, value: value);
    }
    return value;
  }

  Future<void> logout() async {
    try {
      await _client.delete(_uri('/webmail/session'), headers: _headers());
    } finally {
      await clearLocalSession();
    }
  }

  Future<List<MailFolder>> folders() async {
    final responses = await Future.wait<http.Response>([
      _client.get(_uri('/webmail/folders'), headers: _headers()),
      _client.get(_uri('/webmail/folder-counts'), headers: _headers()),
    ]);

    final folderJson = Map<String, dynamic>.from(_decode(responses[0]));
    final countJson = Map<String, dynamic>.from(_decode(responses[1]));

    final totals = <String, int>{};
    final unread = <String, int>{};
    for (final item in (countJson['items'] as List? ?? const [])) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final name = row['name']?.toString() ?? row['folder']?.toString() ?? '';
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      totals[key] = ((row['messages'] ?? row['total'] ?? row['count']) as num?)
              ?.toInt() ??
          0;
      unread[key] = ((row['unseen'] ?? row['unread']) as num?)?.toInt() ?? 0;
    }

    return (folderJson['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) {
          final name = item['name']?.toString() ?? '';
          final key = name.toLowerCase();
          return MailFolder(
            name,
            totalCount: totals[key] ?? 0,
            unreadCount: unread[key] ?? 0,
          );
        })
        .where((folder) => folder.name.isNotEmpty)
        .toList();
  }

  Future<List<MailMessage>> messages({
    String folder = 'INBOX',
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client.get(
      _uri('/webmail/messages', {
        'folder': folder,
        'limit': '$limit',
        'offset': '$offset',
        'q': query,
      }),
      headers: _headers(),
    );
    final decoded = Map<String, dynamic>.from(_decode(response));
    return (decoded['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => MailMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<MailMessage> message(String uid, {String folder = 'INBOX'}) async {
    final response = await _client.get(
      _uri('/webmail/messages/$uid', {'folder': folder}),
      headers: _headers(),
    );
    return MailMessage.fromJson(
      Map<String, dynamic>.from(_decode(response)),
    );
  }

  Future<MailMessage> setFlags(
    String uid, {
    required String folder,
    bool? seen,
    bool? flagged,
    bool? answered,
  }) async {
    final response = await _client.patch(
      _uri('/webmail/messages/$uid/flags', {'folder': folder}),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'seen': seen,
        'flagged': flagged,
        'answered': answered,
      }),
    );
    return MailMessage.fromJson(
      Map<String, dynamic>.from(_decode(response)),
    );
  }

  Future<void> deleteMessage(String uid, {required String folder}) async {
    final response = await _client.delete(
      _uri('/webmail/messages/$uid', {'folder': folder}),
      headers: _headers(),
    );
    _decode(response);
  }

  Future<void> moveMessage(
    String uid, {
    required String folder,
    required String destination,
  }) async {
    final response = await _client.post(
      _uri('/webmail/messages/$uid/move', {'folder': folder}),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'destination': destination}),
    );
    _decode(response);
  }

  Future<Uint8List> downloadAttachment(
    String uid,
    int index, {
    required String folder,
  }) async {
    final response = await _client.get(
      _uri('/webmail/messages/$uid/attachments/$index', {'folder': folder}),
      headers: _headers(),
    );
    _checkBinary(response);
    return response.bodyBytes;
  }

  Future<void> send({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    List<MailUploadAttachment> attachments = const [],
    String inReplyTo = '',
    String references = '',
  }) async {
    final response = await _client.post(
      _uri('/webmail/send'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'to': to,
        'cc': cc,
        'bcc': bcc,
        'subject': subject,
        'body_text': bodyText,
        'attachments': attachments
            .map(
              (item) => {
                'filename': item.filename,
                'content_type': item.contentType,
                'content_b64': base64Encode(item.bytes),
              },
            )
            .toList(),
        'in_reply_to': inReplyTo,
        'references': references,
      }),
    );
    _decode(response);
  }

  Future<void> saveDraft({
    List<String> to = const [],
    List<String> cc = const [],
    String subject = '',
    String bodyText = '',
  }) async {
    final response = await _client.post(
      _uri('/webmail/drafts'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'to': to,
        'cc': cc,
        'subject': subject,
        'body_text': bodyText,
      }),
    );
    _decode(response);
  }

  Future<Map<String, String>> identity() async {
    final response = await _client.get(
      _uri('/webmail/identity'),
      headers: _headers(),
    );
    final decoded = Map<String, dynamic>.from(_decode(response));
    return {
      'address': decoded['address']?.toString() ?? '',
      'display_name': decoded['display_name']?.toString() ?? '',
    };
  }
}
