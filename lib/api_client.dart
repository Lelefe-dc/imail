import 'dart:convert';
import 'dart:io';
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
  bool _externalSession = false;

  static const _cookieStorageKey = 'imail_webmail_session_cookie';
  static const _addressStorageKey = 'imail_webmail_address';
  static const _sessionKindStorageKey = 'imail_webmail_session_kind';

  String? get cachedAddress => _cachedAddress;
  bool get isExternalSession => _externalSession;
  bool get hasSessionCookie => _cookie != null && _cookie!.isNotEmpty;

  String get _mailBase => _externalSession ? '/webmail/external' : '/webmail';

  Future<bool> restoreCookie() async {
    final values = await Future.wait<String?>([
      _storage.read(key: _cookieStorageKey),
      _storage.read(key: _addressStorageKey),
      _storage.read(key: _sessionKindStorageKey),
    ]);
    _cookie = values[0];
    _cachedAddress = values[1];
    _externalSession = values[2] == 'external';
    return hasSessionCookie;
  }

  Future<void> clearLocalSession() async {
    _cookie = null;
    _cachedAddress = null;
    _externalSession = false;
    await Future.wait<void>([
      _storage.delete(key: _cookieStorageKey),
      _storage.delete(key: _addressStorageKey),
      _storage.delete(key: _sessionKindStorageKey),
    ]);
  }

  Map<String, String> _headers({bool jsonBody = false}) => {
        'Accept': 'application/json',
        if (jsonBody) 'Content-Type': 'application/json',
        if (hasSessionCookie) 'Cookie': _cookie!,
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

  Uri _mailUri(String suffix, [Map<String, String?>? query]) =>
      _uri('$_mailBase$suffix', query);

  ApiException _responseException(http.Response response) {
    String message = 'Request failed (${response.statusCode})';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {}
    return ApiException(message, statusCode: response.statusCode);
  }

  dynamic _decode(http.Response response, {bool allowEmpty = false}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (allowEmpty && response.body.trim().isEmpty) return null;
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    }
    throw _responseException(response);
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

  Future<String> _captureSession(
    http.Response response,
    Map<String, dynamic> decoded, {
    required String fallbackAddress,
    required bool external,
  }) async {
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) {
      throw ApiException(
        'The server authenticated the mailbox but did not return a session cookie.',
      );
    }

    _cookie = rawSetCookie.split(';').first.trim();
    _cachedAddress = decoded['address']?.toString() ?? fallbackAddress;
    _externalSession = external;
    await Future.wait<void>([
      _storage.write(key: _cookieStorageKey, value: _cookie),
      _storage.write(key: _addressStorageKey, value: _cachedAddress),
      _storage.write(
        key: _sessionKindStorageKey,
        value: external ? 'external' : 'internal',
      ),
    ]);
    return _cachedAddress!;
  }

  Future<String> login(String address, String password) async {
    final normalized = address.trim().toLowerCase();

    // Known external accounts are checked first because this lookup is a fast
    // Redis profile lookup plus one direct authentication. It does not run
    // discovery. More importantly, a known external account never produces a
    // failed hosted-mailbox login before its real server is tried.
    final knownExternal = await _client.post(
      _uri('/webmail/external/known-session'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'address': normalized, 'password': password}),
    );
    if (knownExternal.statusCode >= 200 && knownExternal.statusCode < 300) {
      final decoded = Map<String, dynamic>.from(_decode(knownExternal));
      return _captureSession(
        knownExternal,
        decoded,
        fallbackAddress: normalized,
        external: true,
      );
    }
    if (knownExternal.statusCode != 404) {
      throw _responseException(knownExternal);
    }

    // Unknown to the external registry: use the normal hosted Ithute mailbox
    // authentication path. A first-time external account is configured through
    // the account-setup screen once and then becomes a known account.
    final internal = await _client.post(
      _uri('/webmail/session'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'address': normalized, 'password': password}),
    );
    if (internal.statusCode >= 200 && internal.statusCode < 300) {
      final decoded = Map<String, dynamic>.from(_decode(internal));
      return _captureSession(
        internal,
        decoded,
        fallbackAddress: normalized,
        external: false,
      );
    }
    throw _responseException(internal);
  }

  Future<void> registerExternalAccount({
    required String address,
    required String password,
    required String username,
    required String displayName,
    required String imapHost,
    required int imapPort,
    required String imapSecurity,
    required String smtpHost,
    required int smtpPort,
    required String smtpSecurity,
  }) async {
    final normalized = address.trim().toLowerCase();
    final response = await _client.post(
      _uri('/webmail/external/register-known'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'address': normalized,
        'password': password,
        'username': username.trim().isEmpty ? normalized : username.trim(),
        'display_name': displayName.trim(),
        'imap_host': imapHost.trim(),
        'imap_port': imapPort,
        'imap_security': imapSecurity,
        'smtp_host': smtpHost.trim(),
        'smtp_port': smtpPort,
        'smtp_security': smtpSecurity,
      }),
    );
    _decode(response);
  }

  Future<String> sessionAddress() async {
    final response = await _client.get(
      _mailUri('/session'),
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
      await _client.delete(_mailUri('/session'), headers: _headers());
    } finally {
      await clearLocalSession();
    }
  }

  Uri realtimeSocketUri({String lastEventId = r'$'}) {
    final httpUri = Uri.parse(baseUrl);
    return httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      path: '${httpUri.path}$_mailBase/events/ws',
      queryParameters: {'last_event_id': lastEventId},
    );
  }

  Future<WebSocket> connectRealtime({String lastEventId = r'$'}) async {
    if (!hasSessionCookie) {
      throw ApiException('No mailbox session is available for realtime mail.');
    }
    final socket = await WebSocket.connect(
      realtimeSocketUri(lastEventId: lastEventId).toString(),
      headers: {'Cookie': _cookie!},
    ).timeout(const Duration(seconds: 8));
    socket.pingInterval = const Duration(seconds: 25);
    return socket;
  }

  Future<List<MailFolder>> folders() async {
    final responses = await Future.wait<http.Response>([
      _client.get(_mailUri('/folders'), headers: _headers()),
      _client.get(_mailUri('/folder-counts'), headers: _headers()),
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
      _mailUri('/messages', {
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
      _mailUri('/messages/$uid', {'folder': folder}),
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
      _mailUri('/messages/$uid/flags', {'folder': folder}),
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
      _mailUri('/messages/$uid', {'folder': folder}),
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
      _mailUri('/messages/$uid/move', {'folder': folder}),
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
      _mailUri('/messages/$uid/attachments/$index', {'folder': folder}),
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
      _mailUri('/send'),
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
      _mailUri('/drafts'),
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
      _mailUri('/identity'),
      headers: _headers(),
    );
    final decoded = Map<String, dynamic>.from(_decode(response));
    return {
      'address': decoded['address']?.toString() ?? '',
      'display_name': decoded['display_name']?.toString() ?? '',
    };
  }
}
