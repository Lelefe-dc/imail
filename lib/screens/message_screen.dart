import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../branding.dart';
import '../mail_store.dart';
import '../models.dart';
import 'compose_screen.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key, required this.seed});

  final MailMessage seed;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  MailMessage? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await context.read<MailStore>().openMessage(widget.seed);
      if (mounted) setState(() => _message = value);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _senderName(String value) {
    final lt = value.indexOf('<');
    final raw = lt > 0 ? value.substring(0, lt) : value.split('@').first;
    final cleaned = raw.replaceAll('"', '').trim();
    return cleaned.isEmpty ? value : cleaned;
  }

  String _senderInitial(String value) {
    final name = _senderName(value).trim();
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

  Future<void> _toggleStar(MailMessage item) async {
    await context.read<MailStore>().toggleStar(item);
    if (mounted) {
      setState(() => _message = item.copyWith(flagged: !item.flagged));
    }
  }

  Future<void> _delete(MailMessage item) async {
    await context.read<MailStore>().delete(item);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _markUnread(MailMessage item) async {
    await context.read<MailStore>().markUnread(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final item = _message ?? widget.seed;
    final store = context.watch<MailStore>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FC),
        surfaceTintColor: const Color(0xFFF3F6FC),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Mark unread',
            onPressed: () => _markUnread(item),
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _delete(item),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              if (value.startsWith('move:')) {
                await context.read<MailStore>().move(item, value.substring(5));
                if (mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (context) => [
              ...store.folders
                  .where((folder) => folder.name != store.selectedFolder)
                  .take(8)
                  .map(
                    (folder) => PopupMenuItem(
                      value: 'move:${folder.name}',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.drive_file_move_outline),
                        title: Text('Move to ${folder.name}'),
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.subject.isEmpty ? '(no subject)' : item.subject,
                              style: const TextStyle(
                                fontSize: 24,
                                height: 1.2,
                                letterSpacing: -0.3,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF272B30),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: item.flagged ? 'Unstar' : 'Star',
                            onPressed: () => _toggleStar(item),
                            icon: Icon(
                              item.flagged
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 29,
                              color: item.flagged
                                  ? imailGold
                                  : const Color(0xFF5E666C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: imailGreen,
                            child: Text(
                              _senderInitial(item.from),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _senderName(item.from),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.from,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF687077),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'to ${item.to}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF687077),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (item.date.isNotEmpty)
                            Flexible(
                              child: Text(
                                item.date,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF747B80),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      if (_message == null)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        SelectableText(
                          item.bodyText.isEmpty ? item.snippet : item.bodyText,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.58,
                            color: Color(0xFF303438),
                          ),
                        ),
                      if (item.attachments.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        const Divider(),
                        const SizedBox(height: 14),
                        const Text(
                          'Attachments',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: item.attachments
                              .map(
                                (attachment) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F8FA),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE1E5E8),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.attach_file_rounded,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(child: Text(attachment.filename)),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFF3F6FC),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(replyTo: item),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.reply_rounded),
                  label: const Text('Reply'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(forward: item),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.forward_rounded),
                  label: const Text('Forward'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
