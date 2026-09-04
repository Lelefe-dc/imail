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

  @override
  Widget build(BuildContext context) {
    final item = _message ?? widget.seed;
    final store = context.watch<MailStore>();
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: item.flagged ? 'Unstar' : 'Star',
            onPressed: () async {
              await context.read<MailStore>().toggleStar(item);
              if (mounted) setState(() => _message = item.copyWith(flagged: !item.flagged));
            },
            icon: Icon(item.flagged ? Icons.star_rounded : Icons.star_border_rounded,
                color: item.flagged ? imailGold : null),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'unread') {
                await context.read<MailStore>().markUnread(item);
                if (mounted) Navigator.pop(context);
              } else if (value == 'delete') {
                await context.read<MailStore>().delete(item);
                if (mounted) Navigator.pop(context);
              } else if (value.startsWith('move:')) {
                await context.read<MailStore>().move(item, value.substring(5));
                if (mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'unread', child: ListTile(leading: Icon(Icons.mark_email_unread_outlined), title: Text('Mark unread'))),
              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Move to Trash'))),
              if (store.folders.where((f) => f.name != store.selectedFolder).isNotEmpty) const PopupMenuDivider(),
              ...store.folders
                  .where((folder) => folder.name != store.selectedFolder)
                  .take(8)
                  .map((folder) => PopupMenuItem(
                        value: 'move:${folder.name}',
                        child: ListTile(leading: const Icon(Icons.drive_file_move_outline), title: Text('Move to ${folder.name}')),
                      )),
            ],
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
              children: [
                Text(item.subject, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: imailGreen)),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: imailGreen,
                      child: Text(item.from.isEmpty ? '?' : item.from.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.from, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text('to ${item.to}', style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B75))),
                          if (item.date.isNotEmpty) Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(item.date, style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B75))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_message == null)
                  const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  SelectableText(item.bodyText.isEmpty ? item.snippet : item.bodyText, style: const TextStyle(fontSize: 16, height: 1.55)),
                if (item.attachments.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Attachments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.attachments
                        .map((attachment) => Chip(
                              avatar: const Icon(Icons.attach_file_rounded, size: 18),
                              label: Text(attachment.filename),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComposeScreen(replyTo: item),
                )),
                icon: const Icon(Icons.reply_rounded),
                label: const Text('Reply'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComposeScreen(forward: item),
                )),
                icon: const Icon(Icons.forward_rounded),
                label: const Text('Forward'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
