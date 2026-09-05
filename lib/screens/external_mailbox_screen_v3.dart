import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../branding.dart';
import '../external_account_store.dart';
import 'external_account_setup_screen.dart';
import 'external_accounts_screen.dart';
import 'external_mailbox_screen_v2.dart' as mailbox_v2;
import 'external_mailbox_settings_screen.dart';

class ExternalMailboxScreen extends StatefulWidget {
  const ExternalMailboxScreen({super.key, required this.account});

  final MailAccount account;

  @override
  State<ExternalMailboxScreen> createState() => _ExternalMailboxScreenState();
}

class _ExternalMailboxScreenState extends State<ExternalMailboxScreen> {
  final _accountStore = ExternalAccountStore();

  String _initial(MailAccount account) {
    final source = account.userName.trim().isNotEmpty
        ? account.userName.trim()
        : account.email.trim();
    return source.isEmpty ? 'M' : source.substring(0, 1).toUpperCase();
  }

  Future<void> _switchTo(MailAccount account) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ExternalMailboxScreen(account: account)),
    );
  }

  Future<void> _connectAnother() async {
    final account = await Navigator.of(context).push<MailAccount>(
      MaterialPageRoute(builder: (_) => const ExternalAccountSetupScreen()),
    );
    if (account == null || !mounted) return;
    await _switchTo(account);
  }

  Future<void> _openSettings() async {
    final removed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExternalMailboxSettingsScreen(account: widget.account),
      ),
    );
    if (removed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openAccountSheet() async {
    final accounts = await _accountStore.loadAccounts();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: imailGreen,
                  foregroundColor: Colors.white,
                  child: Text(_initial(widget.account)),
                ),
                title: Text(
                  widget.account.userName.trim().isNotEmpty
                      ? widget.account.userName
                      : 'Current account',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(widget.account.email),
                trailing: const Icon(
                  Icons.check_circle_rounded,
                  color: imailGreen,
                ),
              ),
              if (accounts.any(
                (item) => item.email.toLowerCase() != widget.account.email.toLowerCase(),
              ))
                const Divider(),
              for (final account in accounts)
                if (account.email.toLowerCase() != widget.account.email.toLowerCase())
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE6F1EC),
                      foregroundColor: imailGreen,
                      child: Text(_initial(account)),
                    ),
                    title: Text(
                      account.userName.trim().isNotEmpty
                          ? account.userName
                          : account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(account.email),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _switchTo(account);
                    },
                  ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.arrow_back_rounded),
                title: const Text('Return to previous account'),
                subtitle: const Text('Go back to the mailbox you were using before this one'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Connect another email account'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _connectAnother();
                },
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Manage connected accounts'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ExternalAccountsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('iMail settings'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSettings();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        mailbox_v2.ExternalMailboxScreen(account: widget.account),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          right: 16,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openAccountSheet,
              child: CircleAvatar(
                radius: 23,
                backgroundColor: imailGreen,
                foregroundColor: Colors.white,
                child: Text(
                  _initial(widget.account),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
