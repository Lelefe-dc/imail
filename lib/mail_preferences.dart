import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MailPreferences {
  MailPreferences({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _conversationKey = 'imail.pref.conversation_view';
  static const _notificationSoundKey = 'imail.pref.notification_sound';
  static const _notificationPreviewKey = 'imail.pref.notification_preview';
  static const _offlineCacheKey = 'imail.pref.offline_cache';
  static const _compactDensityKey = 'imail.pref.compact_density';
  static const _swipeLeftKey = 'imail.pref.swipe_left';
  static const _swipeRightKey = 'imail.pref.swipe_right';

  Future<bool> conversationView() => _readBool(_conversationKey, true);
  Future<bool> notificationSound() => _readBool(_notificationSoundKey, true);
  Future<bool> notificationPreview() => _readBool(_notificationPreviewKey, true);
  Future<bool> offlineCache() => _readBool(_offlineCacheKey, true);
  Future<bool> compactDensity() => _readBool(_compactDensityKey, false);
  Future<String> swipeLeft() => _readString(_swipeLeftKey, 'delete');
  Future<String> swipeRight() => _readString(_swipeRightKey, 'archive');

  Future<void> setConversationView(bool value) =>
      _writeBool(_conversationKey, value);
  Future<void> setNotificationSound(bool value) =>
      _writeBool(_notificationSoundKey, value);
  Future<void> setNotificationPreview(bool value) =>
      _writeBool(_notificationPreviewKey, value);
  Future<void> setOfflineCache(bool value) => _writeBool(_offlineCacheKey, value);
  Future<void> setCompactDensity(bool value) =>
      _writeBool(_compactDensityKey, value);
  Future<void> setSwipeLeft(String value) => _storage.write(
        key: _swipeLeftKey,
        value: _normalizeSwipe(value),
      );
  Future<void> setSwipeRight(String value) => _storage.write(
        key: _swipeRightKey,
        value: _normalizeSwipe(value),
      );

  Future<bool> _readBool(String key, bool fallback) async {
    final value = await _storage.read(key: key);
    if (value == null) return fallback;
    return value == '1' || value.toLowerCase() == 'true';
  }

  Future<String> _readString(String key, String fallback) async {
    final value = await _storage.read(key: key);
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  Future<void> _writeBool(String key, bool value) =>
      _storage.write(key: key, value: value ? '1' : '0');

  String _normalizeSwipe(String value) {
    const allowed = {'archive', 'delete', 'unread', 'none'};
    return allowed.contains(value) ? value : 'none';
  }
}
