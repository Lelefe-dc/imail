import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../branding.dart';
import '../external_account_store.dart';
import 'external_account_setup_screen.dart';
import 'external_mailbox_screen.dart';

class ExternalAccountsScreen extends StatefulWidget {
  const ExternalAccountsScreen({super.key});

  @override
  State<ExternalAccountsScreen> createState() => _ExternalAccountsScreenState();
}

class _ExternalAccountsScreenState extends State<ExternalAccountsScreen> {
  final _store = ExternalAccountStore();
  List<MailAccount> _accounts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await _store.loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _addAccount() async {
    final account = await Navigator.of(context).push<MailAccount>(
      MaterialPageRoute(builder: (_) => const ExternalAccountSetupScreen()),
    );
    if (account == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExternalMailboxScreen(account: account)),
    );
  }

  Future<void> _remove(MailAccount account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
          '${account.email} will be removed from iMail on this device. Messages remain on the mail server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _store.removeAccount(account.email);
    await _load();
  }

  String _initial(MailAccount account) {
    final source = account.userName.trim().isNotEmpty
        ? account.userName.trim()
        : account.email.trim();
    return source.isEmpty ? 'M' : source.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FC),
        surfaceTintColor: const Color(0xFFF3F6FC),
        title: const Text('Other email accounts'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        backgroundColor: imailGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add account'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 120),
                  children: [
                    const Icon(
                      Icons.mark_email_read_outlined,
                      size: 72,
                      color: Color(0xFF8B96A2),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Use iMail with any mail server',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add a Zeecom, cPanel, Plesk, company or other standard IMAP/SMTP account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF667085),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _addAccount,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: imailGreen,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add email account'),
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    itemCount: _accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final account = _accounts[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ExternalMailboxScreen(
                                account: account,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: imailGreen,
                                  child: Text(
                                    _initial(account),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        account.userName.trim().isNotEmpty
                                            ? account.userName
                                            : account.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        account.email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF667085),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove account',
                                  onPressed: () => _remove(account),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
