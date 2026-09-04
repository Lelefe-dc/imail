import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api_client.dart';
import 'mail_store.dart';

/// Keeps iMail attached to the Mailbox-DNS realtime mail socket while the app
/// is in the foreground. HTTP polling in MailStore remains as a safety net, so
/// temporary socket/network failures do not make the mailbox stale.
class MailRealtimeBridge extends StatefulWidget {
  const MailRealtimeBridge({super.key, required this.child});

  final Widget child;

  @override
  State<MailRealtimeBridge> createState() => _MailRealtimeBridgeState();
}

class _MailRealtimeBridgeState extends State<MailRealtimeBridge>
    with WidgetsBindingObserver {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _refreshDebounce;
  String? _accountKey;
  String _cursor = r'$';
  bool _active = true;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _refreshDebounce?.cancel();
    unawaited(_disconnect());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _reconnectTimer?.cancel();
      unawaited(_disconnect(clearAccountKey: false));
      return;
    }
    _scheduleEnsure(delay: Duration.zero);
  }

  Future<void> _disconnect({bool clearAccountKey = true}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    _connecting = false;
    if (clearAccountKey) {
      _accountKey = null;
      _cursor = r'$';
    }
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await socket?.close(WebSocketStatus.normalClosure, 'iMail backgrounded');
    } catch (_) {}
  }

  void _scheduleEnsure({const Duration delay = Duration.zero}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (mounted) unawaited(_ensureSocket());
    });
  }

  Future<void> _ensureSocket() async {
    if (!mounted || !_active || _connecting || _socket != null) return;
    final store = context.read<MailStore>();
    final api = context.read<IMailApiClient>();
    if (!store.authenticated || !api.hasSessionCookie) return;

    final nextKey = '${store.address}|${api.isExternalSession ? 'external' : 'internal'}';
    if (_accountKey != nextKey) {
      _cursor = r'$';
      _accountKey = nextKey;
    }

    _connecting = true;
    try {
      final socket = await api.connectRealtime(lastEventId: _cursor);
      if (!mounted || !_active || _accountKey != nextKey) {
        await socket.close();
        return;
      }
      _socket = socket;
      _subscription = socket.listen(
        (raw) => _onSocketMessage(raw, nextKey),
        onError: (_) => _onSocketClosed(nextKey),
        onDone: () => _onSocketClosed(nextKey),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleEnsure(delay: const Duration(seconds: 3));
    } finally {
      _connecting = false;
    }
  }

  void _onSocketMessage(dynamic raw, String key) {
    if (!mounted || key != _accountKey) return;
    Map<String, dynamic>? event;
    try {
      final decoded = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
      if (decoded is Map) event = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    if (event == null) return;

    final id = event['id']?.toString();
    if (id != null && id.isNotEmpty) _cursor = id;

    final type = event['type']?.toString() ?? '';
    if (type == 'mailbox.changed') {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || key != _accountKey) return;
        final store = context.read<MailStore>();
        if (store.authenticated) unawaited(store.refresh());
      });
    }
  }

  void _onSocketClosed(String key) {
    if (key != _accountKey) return;
    _subscription = null;
    _socket = null;
    if (_active) _scheduleEnsure(delay: const Duration(seconds: 3));
  }

  void _syncAccountState(MailStore store, IMailApiClient api) {
    if (!store.authenticated || !api.hasSessionCookie) {
      if (_socket != null || _accountKey != null) {
        unawaited(_disconnect());
      }
      return;
    }
    final nextKey = '${store.address}|${api.isExternalSession ? 'external' : 'internal'}';
    if (_accountKey != nextKey) {
      unawaited(_disconnect());
      _accountKey = nextKey;
      _cursor = r'$';
    }
    if (_active && _socket == null && !_connecting) {
      _scheduleEnsure(delay: Duration.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    final api = context.read<IMailApiClient>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAccountState(store, api);
    });
    return widget.child;
  }
}
