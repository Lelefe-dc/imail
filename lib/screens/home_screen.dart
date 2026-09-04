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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  IconData _folderIcon(String name) {
    switch (name.toLowerCase()) {
      case 'inbox': return Icons.inbox_rounded;
      case 'sent': return Icons.send_rounded;
      case 'drafts': return Icons.drafts_outlined;
      case 'trash': return Icons.delete_outline_rounded;
      case 'junk':
      case 'spam': return Icons.report_gmailerrorred_rounded;
      case 'archive': return Icons.archive_outlined;
      default: return Icons.folder_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: IMailLogo(width: 225),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [
                    for (final folder in store.folders)
                      ListTile(
                        selected: store.selectedFolder == folder.name,
                        selectedTileColor: const Color(0xFFE8F3ED),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        leading: Icon(_folderIcon(folder.name)),
                        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: folder.count == null ? null : Text('${folder.count}'),
                        onTap: () {
                          Navigator.pop(context);
                          _search.clear();
                          context.read<MailStore>().selectFolder(folder.name);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: imailGreen,
                  child: Text(
                    (store.displayName.isNotEmpty ? store.displayName : store.address ?? 'i').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(store.displayName.isNotEmpty ? store.displayName : 'iMail account'),
                subtitle: Text(store.address ?? ''),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: store.busy ? null : store.logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: imailSurface,
        surfaceTintColor: imailSurface,
        titleSpacing: 0,
        title: Text(store.selectedFolder, style: const TextStyle(fontWeight: FontWeight.w800, color: imailGreen)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: store.busy ? null : store.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SearchBar(
              controller: _search,
              hintText: 'Search ${store.selectedFolder}',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      setState(_search.clear);
                      context.read<MailStore>().search('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(Colors.white),
              side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFE2E8E5))),
              onSubmitted: context.read<MailStore>().search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (store.busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: store.refresh,
              child: store.messages.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 110),
                        Icon(store.query.isEmpty ? Icons.mark_email_read_outlined : Icons.search_off_rounded,
                            size: 64, color: const Color(0xFF9AA6A0)),
                        const SizedBox(height: 14),
                        Text(
                          store.query.isEmpty ? 'No messages here' : 'No matching messages',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 110),
                      itemCount: store.messages.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                      itemBuilder: (context, index) => _MessageTile(item: store.messages[index]),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComposeScreen())),
        backgroundColor: imailGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Compose', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.item});
  final MailMessage item;

  String _sender(String value) {
    final lt = value.indexOf('<');
    final raw = lt > 0 ? value.substring(0, lt) : value.split('@').first;
    return raw.replaceAll('"', '').trim().isEmpty ? value : raw.replaceAll('"', '').trim();
  }

  String _date(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      if (date.year == now.year && date.month == now.month && date.day == now.day) return DateFormat.Hm().format(date);
      if (date.year == now.year) return DateFormat.MMMd().format(date);
      return DateFormat.yMd().format(date);
    } catch (_) {
      try {
        final parsed = DateFormat('EEE, d MMM yyyy HH:mm:ss Z').parse(raw, true).toLocal();
        return DateFormat.MMMd().format(parsed);
      } catch (_) {
        return '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<MailStore>();
    final sender = _sender(item.from);
    return Material(
      color: item.seen ? Colors.white : const Color(0xFFF0F7F3),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MessageScreen(seed: item),
        )),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: item.seen ? const Color(0xFFE5ECE8) : imailGreen,
                foregroundColor: item.seen ? imailGreen : Colors.white,
                child: Text(sender.isEmpty ? '?' : sender.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(sender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: item.seen ? FontWeight.w600 : FontWeight.w800, fontSize: 15.5)),
                        ),
                        const SizedBox(width: 8),
                        Text(_date(item.date), style: const TextStyle(fontSize: 12, color: Color(0xFF68756F))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: item.seen ? FontWeight.w500 : FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.snippet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF68756F), height: 1.3)),
                        ),
                        IconButton(
                          tooltip: item.flagged ? 'Unstar' : 'Star',
                          onPressed: () => store.toggleStar(item),
                          icon: Icon(item.flagged ? Icons.star_rounded : Icons.star_border_rounded,
                              color: item.flagged ? imailGold : const Color(0xFF7E8984)),
                        ),
                      ],
                    ),
                    if (item.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Row(
                          children: [
                            const Icon(Icons.attach_file_rounded, size: 15, color: Color(0xFF68756F)),
                            const SizedBox(width: 4),
                            Text('${item.attachments.length} attachment${item.attachments.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF68756F))),
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
    );
  }
}
