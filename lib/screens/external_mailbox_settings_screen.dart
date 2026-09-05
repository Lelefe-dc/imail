import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../app_lock.dart';
import '../branding.dart';
import '../external_account_store.dart';
import '../mail_preferences.dart';
import 'external_accounts_screen.dart';

class ExternalMailboxSettingsScreen extends StatefulWidget {
  const ExternalMailboxSettingsScreen({
    super.key,
    required this.account,
  });

  final MailAccount account;

  @override
  State<ExternalMailboxSettingsScreen> createState() =>
      _ExternalMailboxSettingsScreenState();
}

class _ExternalMailboxSettingsScreenState
    extends State<ExternalMailboxSettingsScreen> {
  final _preferences = MailPreferences();
  final _accountStore = ExternalAccountStore();
  final _appLock = AppLockService();

  bool _loading = true;
  bool _sound = true;
  bool _preview = true;
  bool _lock = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      _preferences.notificationSound(),
      _preferences.notificationPreview(),
      _appLock.enabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _sound = values[0] as bool;
      _preview = values[1] as bool;
      _lock = values[2] as bool;
      _loading = false;
    });
  }

  Future<void> _toggleLock(bool value) async {
    if (value) {
      final verified = await _appLock.authenticate();
      if (!verified) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'iMail could not confirm the device screen lock. Make sure a PIN, password or device credential is configured.',
              ),
            ),
          );
        }
        return;
      }
    }
    await _appLock.setEnabled(value);
    if (mounted) setState(() => _lock = value);
  }

  Future<void> _removeAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove account from iMail?'),
        content: Text(
          '${widget.account.email} will be removed from this device. The mailbox and its messages will remain on the mail server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _accountStore.removeAccount(widget.account.email);
    if (!mounted) return;
    Navigator.pop(context, true);
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
          ? const Center(child: CircularProgressIndicator(color: imailGreen))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
              children: [
                _Card(
                  title: 'Current account',
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: imailGreen,
                        foregroundColor: Colors.white,
                        child: Text(widget.account.email.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(
                        widget.account.userName.trim().isNotEmpty
                            ? widget.account.userName
                            : widget.account.email,
                      ),
                      subtitle: Text(widget.account.email),
                    ),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('Manage connected accounts'),
                      subtitle: const Text('Add, open or remove saved mail accounts'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ExternalAccountsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFB3261E),
                      ),
                      title: const Text(
                        'Remove this account',
                        style: TextStyle(color: Color(0xFFB3261E)),
                      ),
                      subtitle: const Text('Remove the saved connection from this device'),
                      onTap: _removeAccount,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'Notifications',
                  children: [
                    SwitchListTile.adaptive(
                      value: _sound,
                      title: const Text('Notification sound'),
                      subtitle: const Text('Play an iMail alert for new mail when available.'),
                      onChanged: (value) async {
                        setState(() => _sound = value);
                        await _preferences.setNotificationSound(value);
                      },
                    ),
                    SwitchListTile.adaptive(
                      value: _preview,
                      title: const Text('Show message previews'),
                      subtitle: const Text('Allow sender and subject previews in alerts.'),
                      onChanged: (value) async {
                        setState(() => _preview = value);
                        await _preferences.setNotificationPreview(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'Privacy and security',
                  children: [
                    SwitchListTile.adaptive(
                      value: _lock,
                      secondary: const Icon(Icons.lock_outline_rounded),
                      title: const Text('Lock iMail'),
                      subtitle: const Text(
                        'Require the device screen lock when opening iMail or returning after backgrounding.',
                      ),
                      onChanged: _toggleLock,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

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
