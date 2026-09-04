import 'dart:convert';

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

  static const _cookieStorageKey = 'imail_webmail_session_cookie';

  Future<void> restoreCookie() async {
    _cookie = await _storage.read(key: _cookieStorageKey);
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
    return Uri.parse('$baseUrl$path').replace(queryParameters: values.isEmpty ? null : values);
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
      if (decoded is Map && decoded['detail'] != null) message = decoded['detail'].toString();
    } catch (_) {}
    throw ApiException(message, statusCode: response.statusCode);
  }

  Future<String> login(String address, String password) async {
    final response = await _client.post(
      _uri('/webmail/session'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'address': address.trim().toLowerCase(), 'password': password}),
    );
    final decoded = Map<String, dynamic>.from(_decode(response));
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) {
      throw ApiException('The server authenticated the mailbox but did not return a session cookie.');
    }
    _cookie = rawSetCookie.split(';').first.trim();
    await _storage.write(key: _cookieStorageKey, value: _cookie);
    return decoded['address']?.toString() ?? address.trim().toLowerCase();
  }

  Future<String> sessionAddress() async {
    final response = await _client.get(_uri('/webmail/session'), headers: _headers());
    final decoded = Map<String, dynamic>.from(_decode(response));
    return decoded['address']?.toString() ?? '';
  }

  Future<void> logout() async {
    try {
      await _client.delete(_uri('/webmail/session'), headers: _headers());
    } finally {
      _cookie = null;
      await _storage.delete(key: _cookieStorageKey);
    }
  }

  Future<List<MailFolder>> folders() async {
    final folderResponse = await _client.get(_uri('/webmail/folders'), headers: _headers());
    final countResponse = await _client.get(_uri('/webmail/folder-counts'), headers: _headers());
    final folderJson = Map<String, dynamic>.from(_decode(folderResponse));
    final countJson = Map<String, dynamic>.from(_decode(countResponse));
    final counts = <String, int>{};
    for (final item in (countJson['items'] as List? ?? const [])) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final name = m['name']?.toString() ?? m['folder']?.toString() ?? '';
        final count = (m['unseen'] ?? m['messages'] ?? m['count']) as num?;
        if (name.isNotEmpty && count != null) counts[name] = count.toInt();
      }
    }
    return (folderJson['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) {
          final name = item['name']?.toString() ?? '';
          return MailFolder(name, count: counts[name]);
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
    return MailMessage.fromJson(Map<String, dynamic>.from(_decode(response)));
  }

  Future<MailMessage> setFlags(
    String uid, {
    required String folder,
    bool? seen,
    bool? flagged,
  }) async {
    final response = await _client.patch(
      _uri('/webmail/messages/$uid/flags', {'folder': folder}),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'seen': seen, 'flagged': flagged}),
    );
    return MailMessage.fromJson(Map<String, dynamic>.from(_decode(response)));
  }

  Future<void> deleteMessage(String uid, {required String folder}) async {
    final response = await _client.delete(
      _uri('/webmail/messages/$uid', {'folder': folder}),
      headers: _headers(),
    );
    _decode(response);
  }

  Future<void> moveMessage(String uid, {required String folder, required String destination}) async {
    final response = await _client.post(
      _uri('/webmail/messages/$uid/move', {'folder': folder}),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'destination': destination}),
    );
    _decode(response);
  }

  Future<void> send({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
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
        'attachments': const [],
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
      body: jsonEncode({'to': to, 'cc': cc, 'subject': subject, 'body_text': bodyText}),
    );
    _decode(response);
  }

  Future<Map<String, String>> identity() async {
    final response = await _client.get(_uri('/webmail/identity'), headers: _headers());
    final decoded = Map<String, dynamic>.from(_decode(response));
    return {
      'address': decoded['address']?.toString() ?? '',
      'display_name': decoded['display_name']?.toString() ?? '',
    };
  }
}
