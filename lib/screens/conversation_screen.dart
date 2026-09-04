import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../branding.dart';
import '../mail_conversation.dart';
import '../mail_store.dart';
import '../models.dart';
import 'compose_screen.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversation});

  final MailConversation conversation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final Map<String, MailMessage> _details = {};
  final Set<String> _loading = {};

  String _sender(String value) {
    final lt = value.indexOf('<');
    final raw = lt > 0 ? value.substring(0, lt) : value.split('@').first;
    final cleaned = raw.replaceAll('"', '').trim();
    return cleaned.isEmpty ? value : cleaned;
  }

  String _date(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();
      return DateFormat('d MMM, HH:mm').format(date);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _load(MailMessage seed) async {
    if (_details.containsKey(seed.uid) || _loading.contains(seed.uid)) return;
    setState(() => _loading.add(seed.uid));
    try {
      final message = await context.read<MailStore>().openMessage(seed);
      if (!mounted) return;
      setState(() => _details[seed.uid] = message);
    } catch (_) {
      // Keep the cached/snippet version visible if the network is unavailable.
    } finally {
      if (mounted) setState(() => _loading.remove(seed.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.conversation.messages;
    final latest = messages.first;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          latest.subject.isEmpty ? '(no subject)' : latest.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Reply',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ComposeScreen(replyTo: latest)),
            ),
            icon: const Icon(Icons.reply_rounded),
          ),
          IconButton(
            tooltip: 'Forward',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ComposeScreen(forward: latest)),
            ),
            icon: const Icon(Icons.forward_rounded),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
        itemCount: messages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final seed = messages[index];
          final detail = _details[seed.uid] ?? seed;
          final initiallyExpanded = index == 0;
          if (initiallyExpanded && !_details.containsKey(seed.uid)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _load(seed);
            });
          }
          return Material(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFE5E9E7)),
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: initiallyExpanded,
              onExpansionChanged: (expanded) {
                if (expanded) _load(seed);
              },
              tilePadding: const EdgeInsets.fromLTRB(14, 5, 10, 5),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: imailGreen,
                child: Text(
                  _sender(seed.from).isEmpty
                      ? '?'
                      : _sender(seed.from)[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                _sender(seed.from),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: seed.seen ? FontWeight.w600 : FontWeight.w800,
                ),
              ),
              subtitle: Text(
                '${_date(seed.date)} • to ${seed.to.isEmpty ? 'me' : seed.to}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              children: [
                if (_loading.contains(seed.uid))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    detail.bodyText.isNotEmpty ? detail.bodyText : detail.snippet,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: Color(0xFF24272B),
                    ),
                  ),
                ),
                if (detail.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: detail.attachments
                        .map(
                          (attachment) => Chip(
                            avatar: const Icon(Icons.attach_file_rounded, size: 17),
                            label: Text(attachment.filename),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComposeScreen(replyTo: detail),
                        ),
                      ),
                      icon: const Icon(Icons.reply_rounded),
                      label: const Text('Reply'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComposeScreen(
                            replyTo: detail,
                            replyAll: true,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.reply_all_rounded),
                      label: const Text('Reply all'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
