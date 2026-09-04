import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';

class MailStore extends ChangeNotifier {
  MailStore(this.api);
  final IMailApiClient api;

  bool booting = true;
  bool busy = false;
  String? error;
  String? address;
  String displayName = '';
  String selectedFolder = 'INBOX';
  String query = '';
  List<MailFolder> folders = const [];
  List<MailMessage> messages = const [];

  bool get authenticated => address != null && address!.isNotEmpty;

  Future<void> bootstrap() async {
    booting = true;
    notifyListeners();
    try {
      await api.restoreCookie();
      final restored = await api.sessionAddress();
      if (restored.isNotEmpty) {
        address = restored;
        await _loadMailbox();
      }
    } on ApiException catch (e) {
      if (e.statusCode != 401) error = e.message;
    } catch (_) {
      // First launch or expired secure session: show login without noise.
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      address = await api.login(email, password);
      selectedFolder = 'INBOX';
      query = '';
      await _loadMailbox();
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadMailbox() async {
    final results = await Future.wait<dynamic>([
      api.folders(),
      api.messages(folder: selectedFolder, query: query),
      api.identity(),
    ]);
    folders = results[0] as List<MailFolder>;
    messages = results[1] as List<MailMessage>;
    final identity = results[2] as Map<String, String>;
    displayName = identity['display_name'] ?? '';
    address = identity['address']?.isNotEmpty == true ? identity['address'] : address;
  }

  Future<void> refresh() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        api.folders(),
        api.messages(folder: selectedFolder, query: query),
      ]);
      folders = results[0] as List<MailFolder>;
      messages = results[1] as List<MailMessage>;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectFolder(String folder) async {
    selectedFolder = folder;
    query = '';
    messages = const [];
    notifyListeners();
    await refresh();
  }

  Future<void> search(String value) async {
    query = value.trim();
    await refresh();
  }

  Future<MailMessage> openMessage(MailMessage item) async {
    final detailed = await api.message(item.uid, folder: selectedFolder);
    final index = messages.indexWhere((message) => message.uid == item.uid);
    if (index >= 0) {
      final copy = [...messages];
      copy[index] = detailed;
      messages = copy;
      notifyListeners();
    }
    return detailed;
  }

  Future<void> toggleStar(MailMessage item) async {
    final updated = await api.setFlags(
      item.uid,
      folder: selectedFolder,
      flagged: !item.flagged,
    );
    _replace(updated);
  }

  Future<void> markUnread(MailMessage item) async {
    final updated = await api.setFlags(item.uid, folder: selectedFolder, seen: false);
    _replace(updated);
  }

  void _replace(MailMessage item) {
    final index = messages.indexWhere((message) => message.uid == item.uid);
    if (index < 0) return;
    final copy = [...messages];
    copy[index] = item;
    messages = copy;
    notifyListeners();
  }

  Future<void> delete(MailMessage item) async {
    await api.deleteMessage(item.uid, folder: selectedFolder);
    messages = messages.where((message) => message.uid != item.uid).toList();
    notifyListeners();
  }

  Future<void> move(MailMessage item, String destination) async {
    await api.moveMessage(item.uid, folder: selectedFolder, destination: destination);
    messages = messages.where((message) => message.uid != item.uid).toList();
    notifyListeners();
  }

  Future<void> logout() async {
    busy = true;
    notifyListeners();
    try {
      await api.logout();
    } finally {
      address = null;
      displayName = '';
      selectedFolder = 'INBOX';
      query = '';
      folders = const [];
      messages = const [];
      busy = false;
      notifyListeners();
    }
  }
}
