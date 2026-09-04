import 'package:flutter/material.dart';

import '../branding.dart';
import '../mail_cache.dart';
import '../mail_preferences.dart';
import '../mail_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  final MailStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _preferences = MailPreferences();
  final _cache = MailCache();

  bool _loading = true;
  bool _conversation = true;
  bool _sound = true;
  bool _preview = true;
  bool _offline = true;
  bool _compact = false;
  String _left = 'delete';
  String _right = 'archive';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      _preferences.conversationView(),
      _preferences.notificationSound(),
      _preferences.notificationPreview(),
      _preferences.offlineCache(),
      _preferences.compactDensity(),
      _preferences.swipeLeft(),
      _preferences.swipeRight(),
    ]);
    if (!mounted) return;
    setState(() {
      _conversation = values[0] as bool;
      _sound = values[1] as bool;
      _preview = values[2] as bool;
      _offline = values[3] as bool;
      _compact = values[4] as bool;
      _left = values[5] as String;
      _right = values[6] as String;
      _loading = false;
    });
  }

  Future<void> _setBool(
    bool value,
    Future<void> Function(bool value) writer,
    void Function(bool value) local,
  ) async {
    local(value);
    setState(() {});
    await writer(value);
  }

  Future<void> _clearCache() async {
    final address = widget.store.address ?? '';
    if (address.isEmpty) return;
    await _cache.clearAccount(
      address,
      widget.store.folders.map((folder) => folder.name),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cached mail cleared for this account.')),
    );
  }

  String _label(String value) {
    switch (value) {
      case 'archive':
        return 'Archive';
      case 'delete':
        return 'Delete';
      case 'unread':
        return 'Mark unread';
      default:
        return 'Do nothing';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        title: const Text('iMail settings'),
        backgroundColor: const Color(0xFFF3F6FC),
        surfaceTintColor: const Color(0xFFF3F6FC),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
              children: [
                _SettingsCard(
                  title: 'Reading mail',
                  children: [
                    SwitchListTile.adaptive(
                      value: _conversation,
                      onChanged: (value) => _setBool(
                        value,
                        _preferences.setConversationView,
                        (next) => _conversation = next,
                      ),
                      title: const Text('Conversation view'),
                      subtitle: const Text(
                        'Group related replies into a single conversation.',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: _compact,
                      onChanged: (value) => _setBool(
                        value,
                        _preferences.setCompactDensity,
                        (next) => _compact = next,
                      ),
                      title: const Text('Compact inbox'),
                      subtitle: const Text('Show more messages on screen.'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: 'Notifications',
                  children: [
                    SwitchListTile.adaptive(
                      value: _sound,
                      onChanged: (value) => _setBool(
                        value,
                        _preferences.setNotificationSound,
                        (next) => _sound = next,
                      ),
                      title: const Text('Notification sound'),
                      subtitle: const Text(
                        'Play an alert when realtime mail arrives while iMail is active.',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: _preview,
                      onChanged: (value) => _setBool(
                        value,
                        _preferences.setNotificationPreview,
                        (next) => _preview = next,
                      ),
                      title: const Text('Show message previews'),
                      subtitle: const Text(
                        'Allow sender and subject previews in iMail notifications.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: 'Swipe actions',
                  children: [
                    ListTile(
                      title: const Text('Swipe left'),
                      subtitle: Text(_label(_left)),
                      trailing: DropdownButton<String>(
                        value: _left,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'delete', child: Text('Delete')),
                          DropdownMenuItem(value: 'archive', child: Text('Archive')),
                          DropdownMenuItem(value: 'unread', child: Text('Unread')),
                          DropdownMenuItem(value: 'none', child: Text('None')),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() => _left = value);
                          await _preferences.setSwipeLeft(value);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Swipe right'),
                      subtitle: Text(_label(_right)),
                      trailing: DropdownButton<String>(
                        value: _right,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'archive', child: Text('Archive')),
                          DropdownMenuItem(value: 'delete', child: Text('Delete')),
                          DropdownMenuItem(value: 'unread', child: Text('Unread')),
                          DropdownMenuItem(value: 'none', child: Text('None')),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() => _right = value);
                          await _preferences.setSwipeRight(value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: 'Offline mail',
                  children: [
                    SwitchListTile.adaptive(
                      value: _offline,
                      onChanged: (value) => _setBool(
                        value,
                        _preferences.setOfflineCache,
                        (next) => _offline = next,
                      ),
                      title: const Text('Keep recent mail available offline'),
                      subtitle: const Text(
                        'Cache up to 100 recent messages per folder in encrypted device storage.',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('Clear cached mail'),
                      onTap: _clearCache,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: 'Account',
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: imailGreen,
                        foregroundColor: Colors.white,
                        child: Text(
                          (widget.store.address ?? 'i').substring(0, 1).toUpperCase(),
                        ),
                      ),
                      title: Text(
                        widget.store.displayName.isNotEmpty
                            ? widget.store.displayName
                            : 'iMail account',
                      ),
                      subtitle: Text(widget.store.address ?? ''),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Text(
              title,
              style: const TextStyle(
                color: imailGreen,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
