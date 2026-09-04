import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

class MailContact {
  const MailContact({required this.email, this.name = ''});

  final String email;
  final String name;

  factory MailContact.fromJson(Map<String, dynamic> json) => MailContact(
        email: json['email']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class MailAccountApi {
  MailAccountApi({
    String? baseUrl,
    FlutterSecureStorage? storage,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? const String.fromEnvironment(
          'IMAIL_API_BASE_URL',
          defaultValue: 'https://api.ithute.co.ls/api/v1',
        ))
            .replaceAll(RegExp(r'/+$'), ''),
        _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  final String baseUrl;
  final FlutterSecureStorage _storage;
  final http.Client _client;

  static const _cookieStorageKey = 'imail_webmail_session_cookie';
  static const _sessionKindStorageKey = 'imail_webmail_session_kind';

  Future<({String cookie, String base})> _session() async {
    final values = await Future.wait<String?>([
      _storage.read(key: _cookieStorageKey),
      _storage.read(key: _sessionKindStorageKey),
    ]);
    final cookie = values[0] ?? '';
    if (cookie.isEmpty) throw ApiException('Mailbox session is not available.');
    final path = values[1] == 'external' ? '/webmail/external' : '/webmail';
    return (cookie: cookie, base: path);
  }

  Future<dynamic> _request(
    String suffix, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final session = await _session();
    var uri = Uri.parse('$baseUrl${session.base}$suffix');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Cookie': session.cookie,
      if (body != null) 'Content-Type': 'application/json',
    };
    late final http.Response response;
    switch (method) {
      case 'POST':
        response = await _client.post(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PUT':
        response = await _client.put(uri, headers: headers, body: jsonEncode(body));
        break;
      default:
        response = await _client.get(uri, headers: headers);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Request failed (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {}
      throw ApiException(message, statusCode: response.statusCode);
    }
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body);
  }

  Future<List<MailContact>> contacts([String query = '']) async {
    final decoded = Map<String, dynamic>.from(
      await _request('/contacts', query: {'q': query}),
    );
    return (decoded['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => MailContact.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.email.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveContact(String email, {String name = ''}) async {
    await _request(
      '/contacts',
      method: 'POST',
      body: {'email': email.trim().toLowerCase(), 'name': name.trim()},
    );
  }

  Future<String> signature() async {
    final decoded = Map<String, dynamic>.from(await _request('/signature'));
    return decoded['html']?.toString() ?? '';
  }

  Future<void> setSignature(String html) async {
    await _request('/signature', method: 'PUT', body: {'html': html});
  }

  Future<void> setDisplayName(String value) async {
    await _request(
      '/identity',
      method: 'PUT',
      body: {'display_name': value.trim()},
    );
  }
}
