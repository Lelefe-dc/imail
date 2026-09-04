import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'branding.dart';

class AppLockService {
  AppLockService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _channel = MethodChannel('ls.co.ithute.imail/security');
  static const _enabledKey = 'imail.security.app_lock';

  final FlutterSecureStorage _storage;

  Future<bool> enabled() async {
    final value = await _storage.read(key: _enabledKey);
    return value == '1' || value?.toLowerCase() == 'true';
  }

  Future<void> setEnabled(bool value) =>
      _storage.write(key: _enabledKey, value: value ? '1' : '0');

  Future<bool> authenticate() async {
    try {
      return await _channel.invokeMethod<bool>('authenticate') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _service = AppLockService();
  bool _enabled = false;
  bool _unlocked = false;
  bool _checking = true;
  bool _authenticating = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    final enabled = await _service.enabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _unlocked = !enabled;
      _checking = false;
    });
    if (enabled) unawaited(_unlock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResume());
    }
  }

  Future<void> _handleResume() async {
    final enabled = await _service.enabled();
    if (!mounted) return;
    final leftAt = _backgroundedAt;
    _backgroundedAt = null;

    if (!enabled) {
      setState(() {
        _enabled = false;
        _unlocked = true;
      });
      return;
    }

    final shouldRelock = !_enabled ||
        !_unlocked ||
        (leftAt != null &&
            DateTime.now().difference(leftAt) > const Duration(seconds: 2));
    setState(() {
      _enabled = true;
      if (shouldRelock) _unlocked = false;
    });
    if (shouldRelock) unawaited(_unlock());
  }

  Future<void> _unlock() async {
    if (_authenticating || !_enabled) return;
    setState(() => _authenticating = true);
    final ok = await _service.authenticate();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      if (ok) _unlocked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F6FC),
        body: Center(child: CircularProgressIndicator(color: imailGreen)),
      );
    }
    if (!_enabled || _unlocked) return widget.child;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IMailLogo(width: 230),
                const SizedBox(height: 30),
                const Icon(Icons.lock_outline_rounded, size: 54, color: imailGreen),
                const SizedBox(height: 16),
                const Text(
                  'iMail is locked',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Confirm your device screen lock to open your mail.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF667085), height: 1.4),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _authenticating ? null : _unlock,
                  icon: _authenticating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  label: const Text('Unlock iMail'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
