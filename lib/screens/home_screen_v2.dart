import 'dart:async';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../branding.dart';
import '../external_account_store.dart';
import '../mail_cache.dart';
import '../mail_conversation.dart';
import '../mail_preferences.dart';
import '../mail_store.dart';
import '../models.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';
import 'external_account_setup_screen.dart';
import 'message_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _cache = MailCache();
  final _preferences = MailPreferences();
  final _accountStore = ExternalAccountStore();

  final List<MailMessage> _older = [];
  final List<MailMessage> _cached = [];
  final Set<String> _selected = {};
  final Set<String> _hidden = {};

  String _contextKey = '';
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _conversationView = true;
  bool _compact = false;
  bool _offlineCache = true;
  String _swipeLeft = 'delete';
  String _swipeRight = 'archive';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadPreferences();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final values = await Future.wait<Object>([
      _preferences.conversationView(),
      _preferences.compactDensity(),
      _preferences.offlineCache(),
      _preferences.swipeLeft(),
      _preferences.swipeRight(),
    ]);
    if (!mounted) return;
    setState(() {
      _conversationView = values[0] as bool;
      _compact = values[1] as bool;
      _offlineCache = values[2] as bool;
      _swipeLeft = values[3] as String;
      _swipeRight = values[4] as String;
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.extentAfter < 650) {
      unawaited(_loadMore());
    }
  }

  List<MailMessage> _dedupe(Iterable<MailMessage> values) {
    final seen = <String>{};
    final rows = <MailMessage>[];
    for (final item in values) {
      if (item.uid.isEmpty || !seen.add(item.uid) || _hidden.contains(item.uid)) {
        continue;
      }
      rows.add(item);
    }
    return rows;
  }

  List<MailMessage> _visibleMessages(MailStore store) {
    final live = _dedupe([...store.messages, ..._older]);
    if (live.isNotEmpty) return live;
    return _dedupe(_cached);
  }

  void _ensureContext(MailStore store) {
    final address = store.address ?? '';
    final key = '$address|${store.selectedFolder}|${store.query}';
    if (_contextKey == key) return;
    _contextKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _contextKey != key) return;
      setState(() {
        _older.clear();
        _cached.clear();
        _selected.clear();
        _hidden.clear();
        _hasMore = true;
      });
      if (_offlineCache && address.isNotEmpty && store.query.isEmpty) {
        final cached = await _cache.load(address, store.selectedFolder);
        if (!mounted || _contextKey != key || cached.isEmpty) return;
        setState(() => _cached.addAll(cached));
      }
    });
  }

  Future<void> _saveCache(MailStore store) async {
    if (!_offlineCache || store.query.isNotEmpty || (store.address ?? '').isEmpty) {
      return;
    }
    final rows = _visibleMessages(store);
    if (rows.isEmpty) return;
    await _cache.save(store.address!, store.selectedFolder, rows);
  }

  Future<void> _loadMore() async {
    if (!mounted || _loadingMore || !_hasMore) return;
    final store = context.read<MailStore>();
    if (!store.authenticated) return;
    setState(() => _loadingMore = true);
    try {
      final current = _visibleMessages(store);
      final more = await context.read<IMailApiClient>().messages(
            folder: store.selectedFolder,
            query: store.query,
            limit: 50,
            offset: current.length,
          );
      if (!mounted) return;
      final existing = current.map((item) => item.uid).toSet();
      final fresh = more.where((item) => existing.add(item.uid)).toList();
      setState(() {
        _older.addAll(fresh);
        _hasMore = more.length >= 50 && fresh.isNotEmpty;
      });
      unawaited(_saveCache(store));
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  MailFolder? _archiveFolder(MailStore store) {
    for (final folder in store.folders) {
      if (folder.name.toLowerCase().contains('archive')) return folder;
    }
    return null;
  }

  Future<void> _applyAction(String action, List<MailMessage> messages) async {
    if (action == 'none' || messages.isEmpty) return;
    final store = context.read<MailStore>();
    try {
      if (action == 'archive') {
        final archive = _archiveFolder(store);
        if (archive == null) {
          _toast('Archive is not available for this mailbox.');
          return;
        }
        for (final message in messages) {
          await store.move(message, archive.name);
        }
      } else if (action == 'delete') {
        for (final message in messages) {
          await store.delete(message);
        }
      } else if (action == 'unread') {
        for (final message in messages) {
          if (message.seen) await store.markUnread(message);
        }
      } else if (action == 'read') {
        final api = context.read<IMailApiClient>();
        for (final message in messages) {
          if (!message.seen) {
            await api.setFlags(
              message.uid,
              folder: store.selectedFolder,
              seen: true,
            );
          }
        }
        await store.refresh();
      } else if (action == 'star') {
        for (final message in messages) {
          if (!message.flagged) await store.toggleStar(message);
        }
      }
    } on ApiException catch (e) {
      _toast(e.message);
      rethrow;
    }
  }

  Future<void> _swipeAction(
    String action,
    List<MailMessage> messages,
  ) async {
    if (action == 'none') return;
    final uids = messages.map((message) => message.uid).toSet();
    setState(() => _hidden.addAll(uids));
    try {
      await _applyAction(action, messages);
      _toast(action == 'delete'
          ? 'Message moved to Trash'
          : action == 'archive'
              ? 'Message archived'
              : 'Message marked unread');
    } catch (_) {
      if (mounted) setState(() => _hidden.removeAll(uids));
    }
  }

  void _toggleSelection(List<MailMessage> messages) {
    final uids = messages.map((message) => message.uid).where((uid) => uid.isNotEmpty).toSet();
    final selected = uids.isNotEmpty && uids.every(_selected.contains);
    setState(() {
      if (selected) {
        _selected.removeAll(uids);
      } else {
        _selected.addAll(uids);
      }
    });
  }

  List<MailMessage> _selectedMessages(MailStore store) => _visibleMessages(store)
      .where((message) => _selected.contains(message.uid))
      .toList(growable: false);

  Future<void> _bulk(String action) async {
    final store = context.read<MailStore>();
    final rows = _selectedMessages(store);
    await _applyAction(action, rows);
    if (mounted) setState(() => _selected.clear());
  }

  IconData _folderIcon(String name) {
    final lower = name.toLowerCase();
    if (lower == 'inbox') return Icons.inbox_rounded;
    if (lower.contains('sent')) return Icons.send_rounded;
    if (lower.contains('draft')) return Icons.drafts_outlined;
    if (lower.contains('trash') || lower == 'bin') return Icons.delete_outline_rounded;
    if (lower.contains('spam') || lower.contains('junk')) return Icons.report_outlined;
    if (lower.contains('archive')) return Icons.archive_outlined;
    return Icons.folder_outlined;
  }

  String _sender(String value) {
    final lt = value.indexOf('<');
    final raw = lt > 0 ? value.substring(0, lt) : value.split('@').first;
    final cleaned = raw.replaceAll('"', '').trim();
    return cleaned.isEmpty ? value : cleaned;
  }

  String _date(String raw) {
    try {
      final value = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      if (value.year == now.year && value.month == now.month && value.day == now.day) {
        return DateFormat.jm().format(value);
      }
      if (value.year == now.year) return DateFormat.MMMd().format(value);
      return DateFormat.yMd().format(value);
    } catch (_) {
      return '';
    }
  }

  String _initial(String source) {
    final text = source.trim();
    return text.isEmpty ? 'I' : text[0].toUpperCase();
  }

  Future<void> _switchExternal(MailAccount account) async {
    final authentication = account.incoming.authentication;
    if (authentication is! PlainAuthentication) {
      _toast('This account uses an authentication method that needs to be connected again.');
      return;
    }
    Navigator.of(context).pop();
    final store = context.read<MailStore>();
    try {
      await store.login(account.email, authentication.password);
    } on ApiException {
      final synced = await _accountStore.syncKnownAccount(account);
      if (!synced) {
        _toast('Could not reconnect this account. Open account setup and verify it again.');
        return;
      }
      try {
        await store.login(account.email, authentication.password);
      } on ApiException catch (e) {
        _toast(e.message);
      }
    }
  }

  Future<void> _addAccount() async {
    Navigator.of(context).pop();
    final account = await Navigator.of(context).push<MailAccount>(
      MaterialPageRoute(builder: (_) => const ExternalAccountSetupScreen()),
    );
    if (account == null || !mounted) return;
    await _switchExternalFromPage(account);
  }

  Future<void> _switchExternalFromPage(MailAccount account) async {
    final auth = account.incoming.authentication;
    if (auth is! PlainAuthentication) {
      _toast('This account needs an interactive sign-in.');
      return;
    }
    try {
      await context.read<MailStore>().login(account.email, auth.password);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _openAccountSheet(MailStore store) async {
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
                  child: Text(_initial(store.displayName.isNotEmpty ? store.displayName : store.address ?? 'i')),
                ),
                title: Text(
                  store.displayName.isNotEmpty ? store.displayName : 'Current account',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(store.address ?? ''),
                trailing: const Icon(Icons.check_circle_rounded, color: imailGreen),
              ),
              if (accounts.isNotEmpty) const Divider(),
              for (final account in accounts)
                if (account.email.toLowerCase() != (store.address ?? '').toLowerCase())
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE6F1EC),
                      foregroundColor: imailGreen,
                      child: Text(_initial(account.userName.isNotEmpty ? account.userName : account.email)),
                    ),
                    title: Text(
                      account.userName.isNotEmpty ? account.userName : account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(account.email),
                    onTap: () => _switchExternal(account),
                  ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Connect another email account'),
                onTap: _addAccount,
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('iMail settings'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SettingsScreen(store: store)),
                  );
                  if (mounted) await _loadPreferences();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await store.logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(MailStore store) {
    final count = _selected.length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Clear selection',
            onPressed: () => setState(() => _selected.clear()),
            icon: const Icon(Icons.close_rounded),
          ),
          Text('$count', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(
            tooltip: 'Archive',
            onPressed: _archiveFolder(store) == null ? null : () => _bulk('archive'),
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _bulk('delete'),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            tooltip: 'Mark unread',
            onPressed: () => _bulk('unread'),
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
            tooltip: 'Mark read',
            onPressed: () => _bulk('read'),
            icon: const Icon(Icons.drafts_outlined),
          ),
          IconButton(
            tooltip: 'Star',
            onPressed: () => _bulk('star'),
            icon: const Icon(Icons.star_border_rounded),
          ),
        ],
      ),
    );
  }

  Widget _mailRow({
    required MailStore store,
    required List<MailMessage> messages,
  }) {
    final seed = messages.first;
    final selected = messages.every((message) => _selected.contains(message.uid));
    final unread = messages.any((message) => !message.seen);
    final flagged = messages.any((message) => message.flagged);
    final sender = _sender(seed.from);
    final dismissKey = messages.map((message) => message.uid).join('-');

    return Dismissible(
      key: ValueKey('mail-$dismissKey'),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        action: _swipeRight,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        action: _swipeLeft,
      ),
      confirmDismiss: (direction) async {
        final action = direction == DismissDirection.startToEnd ? _swipeRight : _swipeLeft;
        if (action == 'none') return false;
        await _swipeAction(action, messages);
        return true;
      },
      child: Material(
        color: selected ? const Color(0xFFDDECE6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onLongPress: () => _toggleSelection(messages),
          onTap: () {
            if (_selected.isNotEmpty) {
              _toggleSelection(messages);
              return;
            }
            if (_conversationView && messages.length > 1) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ConversationScreen(
                    conversation: MailConversation(
                      key: dismissKey,
                      messages: messages,
                    ),
                  ),
                ),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MessageScreen(seed: seed)),
              );
            }
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, _compact ? 10 : 14, 7, _compact ? 9 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _toggleSelection(messages),
                  child: CircleAvatar(
                    radius: _compact ? 19 : 22,
                    backgroundColor: selected ? imailGreen : const Color(0xFF597EAE),
                    foregroundColor: Colors.white,
                    child: selected
                        ? const Icon(Icons.check_rounded)
                        : Text(
                            sender.isEmpty ? '?' : sender[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (messages.length > 1) ...[
                            Container(
                              margin: const EdgeInsets.only(right: 7),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8EEF4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${messages.length}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                          Text(
                            _date(seed.date),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        seed.subject.isEmpty ? '(no subject)' : seed.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              seed.snippet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF667085), fontSize: 13.5),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: flagged ? 'Starred' : 'Star',
                            onPressed: () async {
                              for (final message in messages) {
                                if (message.flagged == flagged) {
                                  await store.toggleStar(message);
                                }
                              }
                            },
                            icon: Icon(
                              flagged ? Icons.star_rounded : Icons.star_border_rounded,
                              color: flagged ? imailGold : const Color(0xFF6A7278),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    _ensureContext(store);
    final rows = _visibleMessages(store);
    if (store.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_saveCache(store));
      });
    }
    final conversations = _conversationView ? groupMailConversations(rows) : const <MailConversation>[];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF3F6FC),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Align(alignment: Alignment.centerLeft, child: IMailLogo(width: 190)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final folder in store.folders)
                      ListTile(
                        selected: folder.name == store.selectedFolder,
                        selectedTileColor: const Color(0xFFE2F0E9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        leading: Icon(_folderIcon(folder.name)),
                        title: Text(folder.name),
                        trailing: folder.count > 0 ? Text('${folder.count}') : null,
                        onTap: () {
                          Navigator.pop(context);
                          _search.clear();
                          store.selectFolder(folder.name);
                        },
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SettingsScreen(store: store)),
                        );
                        if (mounted) await _loadPreferences();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_selected.isNotEmpty)
              _selectionBar(store)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Folders',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(Icons.menu_rounded, size: 29),
                    ),
                    Expanded(
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: TextField(
                          controller: _search,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) => store.search(value),
                          decoration: InputDecoration(
                            hintText: 'Search mail — try from:, subject:, is:unread',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _search.clear();
                                      store.search('');
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _openAccountSheet(store),
                      child: CircleAvatar(
                        radius: 23,
                        backgroundColor: imailGreen,
                        foregroundColor: Colors.white,
                        child: Text(
                          _initial(store.displayName.isNotEmpty ? store.displayName : store.address ?? 'i'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      store.query.isNotEmpty
                          ? 'Search results'
                          : store.selectedFolder.toUpperCase() == 'INBOX'
                              ? 'Primary'
                              : store.selectedFolder,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF30343A),
                      ),
                    ),
                  ),
                  if (_cached.isNotEmpty && store.messages.isEmpty)
                    const Chip(
                      avatar: Icon(Icons.offline_bolt_outlined, size: 16),
                      label: Text('Offline'),
                    ),
                ],
              ),
            ),
            if (store.busy)
              const LinearProgressIndicator(minHeight: 2, color: imailEmerald),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _older.clear();
                    _hasMore = true;
                  });
                  await store.refresh();
                  await _saveCache(store);
                },
                child: rows.isEmpty && !store.busy
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 130),
                          Icon(Icons.inbox_outlined, size: 66, color: Color(0xFF879199)),
                          SizedBox(height: 14),
                          Text(
                            'No mail here',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                        itemCount: (_conversationView ? conversations.length : rows.length) + 1,
                        itemBuilder: (context, index) {
                          final length = _conversationView ? conversations.length : rows.length;
                          if (index == length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator(strokeWidth: 2)
                                    : !_hasMore && rows.isNotEmpty
                                        ? const Text('You are all caught up', style: TextStyle(color: Color(0xFF7A8388)))
                                        : const SizedBox.shrink(),
                              ),
                            );
                          }
                          final messages = _conversationView
                              ? conversations[index].messages
                              : <MailMessage>[rows[index]];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _mailRow(store: store, messages: messages),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'compose',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ComposeScreen()),
        ),
        backgroundColor: const Color(0xFFDDF1E7),
        foregroundColor: imailGreen,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Compose', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.alignment, required this.action});

  final Alignment alignment;
  final String action;

  IconData get icon {
    switch (action) {
      case 'archive':
        return Icons.archive_outlined;
      case 'delete':
        return Icons.delete_outline_rounded;
      case 'unread':
        return Icons.mark_email_unread_outlined;
      default:
        return Icons.block_outlined;
    }
  }

  String get label {
    switch (action) {
      case 'archive':
        return 'Archive';
      case 'delete':
        return 'Delete';
      case 'unread':
        return 'Unread';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: action == 'delete' ? const Color(0xFFFCE8E6) : const Color(0xFFE2F1EA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: action == 'delete' ? const Color(0xFFB3261E) : imailGreen),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}
