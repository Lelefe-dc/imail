import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../branding.dart';
import '../mail_store.dart';
import '../models.dart';
import 'compose_screen.dart';
import 'message_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _pageBackground = Color(0xFFF3F6FC);
  static const _muted = Color(0xFF667085);
  static const _unreadDot = Color(0xFF0B74B8);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  IconData _folderIcon(String name) {
    switch (name.toLowerCase()) {
      case 'inbox':
        return Icons.inbox_rounded;
      case 'sent':
        return Icons.send_rounded;
      case 'drafts':
        return Icons.drafts_outlined;
      case 'trash':
        return Icons.delete_outline_rounded;
      case 'junk':
      case 'spam':
        return Icons.report_gmailerrorred_rounded;
      case 'archive':
        return Icons.archive_outlined;
      case 'promotions':
        return Icons.local_offer_outlined;
      case 'updates':
        return Icons.info_outline_rounded;
      case 'social':
        return Icons.people_outline_rounded;
      default:
        return Icons.folder_outlined;
    }
  }

  String _sectionTitle(MailStore store) {
    if (store.query.isNotEmpty) return 'Search results';
    return store.selectedFolder.toUpperCase() == 'INBOX'
        ? 'Primary'
        : store.selectedFolder;
  }

  List<MailFolder> _categoryFolders(MailStore store) {
    if (store.selectedFolder.toUpperCase() != 'INBOX' || store.query.isNotEmpty) {
      return const [];
    }
    const names = {'updates', 'promotions', 'social'};
    return store.folders
        .where((folder) => names.contains(folder.name.toLowerCase()))
        .toList();
  }

  int? _inboxCount(MailStore store) {
    for (final folder in store.folders) {
      if (folder.name.toUpperCase() == 'INBOX') return folder.count;
    }
    return null;
  }

  Future<void> _openAccountSheet(MailStore store) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: imailGreen,
                child: Text(
                  _accountInitial(store),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                store.displayName.isNotEmpty
                    ? store.displayName
                    : 'iMail account',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(store.address ?? '', style: const TextStyle(color: _muted)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: store.busy
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await store.logout();
                      },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _accountInitial(MailStore store) {
    final source = store.displayName.isNotEmpty
        ? store.displayName
        : (store.address ?? 'i');
    return source.trim().isEmpty ? 'I' : source.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    final categories = _categoryFolders(store);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _pageBackground,
      drawer: _MailDrawer(
        store: store,
        folderIcon: _folderIcon,
        onSelectFolder: (folder) {
          Navigator.pop(context);
          _search.clear();
          context.read<MailStore>().selectFolder(folder);
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Mail folders',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu_rounded, size: 31),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: context.read<MailStore>().search,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Search in mail',
                          hintStyle: const TextStyle(
                            color: Color(0xFF3F4348),
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 17,
                          ),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                    context.read<MailStore>().search('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openAccountSheet(store),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: imailGreen,
                      child: Text(
                        _accountInitial(store),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 24, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _sectionTitle(store),
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: Color(0xFF30343A),
                  ),
                ),
              ),
            ),
            if (store.busy)
              const LinearProgressIndicator(
                minHeight: 2,
                color: imailEmerald,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: RefreshIndicator(
                color: imailGreen,
                onRefresh: store.refresh,
                child: store.messages.isEmpty && categories.isEmpty
                    ? _EmptyMailbox(store: store)
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 128),
                        itemCount: categories.length + store.messages.length,
                        itemBuilder: (context, index) {
                          if (index < categories.length) {
                            final category = categories[index];
                            return _CategoryCard(
                              folder: category,
                              icon: _folderIcon(category.name),
                              onTap: () {
                                _search.clear();
                                context.read<MailStore>().selectFolder(category.name);
                              },
                            );
                          }
                          return _MessageCard(
                            item: store.messages[index - categories.length],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FloatingActionButton.extended(
          heroTag: 'compose',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ComposeScreen()),
          ),
          elevation: 5,
          backgroundColor: const Color(0xFFDFF3E9),
          foregroundColor: imailGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(Icons.edit_rounded, size: 27),
          label: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Compose',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _MailBottomBar(
        inboxCount: _inboxCount(store),
        onMailTap: () {
          final inbox = store.folders.where(
            (folder) => folder.name.toUpperCase() == 'INBOX',
          );
          if (inbox.isNotEmpty && store.selectedFolder != inbox.first.name) {
            _search.clear();
            context.read<MailStore>().selectFolder(inbox.first.name);
          }
        },
      ),
    );
  }
}

class _MailDrawer extends StatelessWidget {
  const _MailDrawer({
    required this.store,
    required this.folderIcon,
    required this.onSelectFolder,
  });

  final MailStore store;
  final IconData Function(String) folderIcon;
  final ValueChanged<String> onSelectFolder;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      width: MediaQuery.sizeOf(context).width * 0.84,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 14, 22, 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IMailLogo(width: 205),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                children: [
                  for (final folder in store.folders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: ListTile(
                        selected: store.selectedFolder == folder.name,
                        selectedTileColor: const Color(0xFFE1F0E8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                        leading: Icon(
                          folderIcon(folder.name),
                          color: store.selectedFolder == folder.name
                              ? imailGreen
                              : const Color(0xFF4D5651),
                        ),
                        title: Text(
                          folder.name,
                          style: TextStyle(
                            fontWeight: store.selectedFolder == folder.name
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        trailing: folder.count == null
                            ? null
                            : Text(
                                '${folder.count}',
                                style: const TextStyle(
                                  color: Color(0xFF59635E),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        onTap: () => onSelectFolder(folder.name),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: imailGreen,
                    child: Text(
                      (store.displayName.isNotEmpty
                                  ? store.displayName
                                  : store.address ?? 'i')
                              .trim()
                              .substring(0, 1)
                              .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.displayName.isNotEmpty
                              ? store.displayName
                              : 'iMail account',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          store.address ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6C756F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.folder,
    required this.icon,
    required this.onTap,
  });

  final MailFolder folder;
  final IconData icon;
  final VoidCallback onTap;

  Color get _accent {
    switch (folder.name.toLowerCase()) {
      case 'promotions':
        return const Color(0xFF118A4A);
      case 'updates':
        return const Color(0xFFE36D05);
      case 'social':
        return const Color(0xFF2A72D8);
      default:
        return imailGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 17, 18, 17),
            child: Row(
              children: [
                Icon(icon, color: _accent, size: 29),
                const SizedBox(width: 22),
                Expanded(
                  child: Text(
                    folder.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if ((folder.count ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      '${folder.count} new',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.item});

  final MailMessage item;

  String _sender(String value) {
    final lt = value.indexOf('<');
    final raw = lt > 0 ? value.substring(0, lt) : value.split('@').first;
    final cleaned = raw.replaceAll('"', '').trim();
    return cleaned.isEmpty ? value : cleaned;
  }

  String _date(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return DateFormat.jm().format(date);
      }
      if (date.year == now.year) return DateFormat.MMMd().format(date);
      return DateFormat.yMd().format(date);
    } catch (_) {
      try {
        final parsed = DateFormat('EEE, d MMM yyyy HH:mm:ss Z')
            .parse(raw, true)
            .toLocal();
        return DateFormat.MMMd().format(parsed);
      } catch (_) {
        return '';
      }
    }
  }

  Color _avatarColor(String sender) {
    const palette = [
      Color(0xFF5D8FEF),
      Color(0xFF7D8A91),
      Color(0xFF9B6CC4),
      Color(0xFF2F9B77),
      Color(0xFFD47C43),
      Color(0xFF5478A7),
    ];
    final index = sender.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<MailStore>();
    final sender = _sender(item.from);
    final unread = !item.seen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MessageScreen(seed: item)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 8, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: _avatarColor(sender),
                  foregroundColor: Colors.white,
                  child: Text(
                    sender.isEmpty ? '?' : sender.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              sender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16.5,
                                height: 1.15,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: const Color(0xFF24272B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _date(item.date),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                              color: const Color(0xFF5F656B),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: _HomeScreenState._unreadDot,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (item.draft) ...[
                            const Text(
                              'Draft',
                              style: TextStyle(
                                color: Color(0xFFCE3A34),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          Expanded(
                            child: Text(
                              item.subject.isEmpty ? '(no subject)' : item.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.2,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: const Color(0xFF30343A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.snippet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF61666B),
                                fontSize: 14.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: item.flagged ? 'Unstar' : 'Star',
                            onPressed: () => store.toggleStar(item),
                            icon: Icon(
                              item.flagged
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 28,
                              color: item.flagged
                                  ? imailGold
                                  : const Color(0xFF5D646A),
                            ),
                          ),
                        ],
                      ),
                      if (item.attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.attach_file_rounded,
                                size: 15,
                                color: Color(0xFF6C7378),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${item.attachments.length} attachment${item.attachments.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6C7378),
                                ),
                              ),
                            ],
                          ),
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
}

class _EmptyMailbox extends StatelessWidget {
  const _EmptyMailbox({required this.store});

  final MailStore store;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 90, 24, 140),
      children: [
        Icon(
          store.query.isEmpty
              ? Icons.mark_email_read_outlined
              : Icons.search_off_rounded,
          size: 68,
          color: const Color(0xFF9AA6A0),
        ),
        const SizedBox(height: 16),
        Text(
          store.query.isEmpty ? 'No messages here' : 'No matching messages',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF343A37),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          store.query.isEmpty
              ? 'Pull down to refresh your mailbox.'
              : 'Try a different search term.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF727C77)),
        ),
      ],
    );
  }
}

class _MailBottomBar extends StatelessWidget {
  const _MailBottomBar({required this.inboxCount, required this.onMailTap});

  final int? inboxCount;
  final VoidCallback onMailTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 76,
        color: const Color(0xFFF3F6FC),
        padding: const EdgeInsets.fromLTRB(90, 7, 90, 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onMailTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 62,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8EEF7),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.mail_rounded,
                      color: imailGreen,
                      size: 27,
                    ),
                  ),
                  if ((inboxCount ?? 0) > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB3261E),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          (inboxCount ?? 0) > 99 ? '99+' : '${inboxCount ?? 0}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Video meetings',
              onPressed: null,
              icon: const Icon(Icons.videocam_outlined, size: 29),
            ),
          ],
        ),
      ),
    );
  }
}
