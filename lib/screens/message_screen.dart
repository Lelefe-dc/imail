import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
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
  bool _downloading = false;

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

  String _senderAddress(String value) {
    final match = RegExp(r'<([^>]+)>').firstMatch(value);
    if (match != null) return match.group(1)!.trim();
    final email = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).firstMatch(value);
    return email?.group(0) ?? value;
  }

  String _senderInitial(String value) {
    final name = _senderName(value).trim();
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

  Future<void> _toggleStar(MailMessage item) async {
    try {
      await context.read<MailStore>().toggleStar(item);
      if (mounted) {
        setState(() => _message = item.copyWith(flagged: !item.flagged));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _archive(MailMessage item) async {
    try {
      await context.read<MailStore>().move(item, 'Archive');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _delete(MailMessage item) async {
    try {
      await context.read<MailStore>().delete(item);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _markUnread(MailMessage item) async {
    try {
      await context.read<MailStore>().markUnread(item);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _move(MailMessage item, String destination) async {
    try {
      await context.read<MailStore>().move(item, destination);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _downloadAttachment(
    MailMessage item,
    MailAttachment attachment,
  ) async {
    if (_downloading) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save attachment',
      fileName: attachment.filename,
    );
    if (path == null || !mounted) return;

    setState(() => _downloading = true);
    try {
      final bytes = await context.read<MailStore>().api.downloadAttachment(
            item.uid,
            attachment.index,
            folder: context.read<MailStore>().selectedFolder,
          );
      await File(path).writeAsBytes(bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${attachment.filename}')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the attachment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showRecipientDetails(MailMessage item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Message details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              _DetailRow(label: 'From', value: item.from),
              _DetailRow(label: 'To', value: item.to),
              if (item.cc.isNotEmpty) _DetailRow(label: 'Cc', value: item.cc),
              if (item.date.isNotEmpty) _DetailRow(label: 'Date', value: item.date),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _message ?? widget.seed;
    final store = context.watch<MailStore>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 30),
        ),
        actions: [
          IconButton(
            tooltip: 'Archive',
            onPressed: () => _archive(item),
            icon: const Icon(Icons.archive_outlined, size: 27),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _delete(item),
            icon: const Icon(Icons.delete_outline_rounded, size: 27),
          ),
          IconButton(
            tooltip: 'Mark unread',
            onPressed: () => _markUnread(item),
            icon: const Icon(Icons.mark_email_unread_outlined, size: 27),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'reply') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(replyTo: item),
                  ),
                );
              } else if (value == 'reply-all') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(replyTo: item, replyAll: true),
                  ),
                );
              } else if (value == 'forward') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(forward: item),
                  ),
                );
              } else if (value.startsWith('move:')) {
                _move(item, value.substring(5));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reply', child: Text('Reply')),
              const PopupMenuItem(value: 'reply-all', child: Text('Reply all')),
              const PopupMenuItem(value: 'forward', child: Text('Forward')),
              const PopupMenuDivider(),
              ...store.folders
                  .where((folder) => folder.name != store.selectedFolder)
                  .take(10)
                  .map(
                    (folder) => PopupMenuItem(
                      value: 'move:${folder.name}',
                      child: Text('Move to ${folder.name}'),
                    ),
                  ),
            ],
            icon: const Icon(Icons.more_vert_rounded, size: 28),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.subject.isEmpty ? '(no subject)' : item.subject,
                        style: const TextStyle(
                          fontSize: 24,
                          height: 1.25,
                          letterSpacing: -0.25,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF202124),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: item.flagged ? 'Unstar' : 'Star',
                      onPressed: () => _toggleStar(item),
                      icon: Icon(
                        item.flagged ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 29,
                        color: item.flagged
                            ? imailGold
                            : const Color(0xFF5F6368),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFFDB4437),
                      child: Text(
                        _senderInitial(item.from),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showRecipientDetails(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _senderName(item.from),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF202124),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '<${_senderAddress(item.from)}>',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF5F6368),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'to ${item.to}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF5F6368),
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: Color(0xFF5F6368),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reply',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComposeScreen(replyTo: item),
                        ),
                      ),
                      icon: const Icon(Icons.reply_rounded, size: 26),
                    ),
                  ],
                ),
                if (item.date.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 57),
                    child: Text(
                      item.date,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF70757A),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
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
                      height: 1.55,
                      color: Color(0xFF202124),
                    ),
                  ),
                if (item.attachments.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 14),
                  Text(
                    '${item.attachments.length} attachment${item.attachments.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: item.attachments
                        .map(
                          (attachment) => InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _downloading
                                ? null
                                : () => _downloadAttachment(item, attachment),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 260),
                              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFDADCE0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.insert_drive_file_outlined),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      attachment.filename,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.download_rounded, size: 21),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: _MailActionButton(
                  icon: Icons.reply_rounded,
                  label: 'Reply',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(replyTo: item),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MailActionButton(
                  icon: Icons.reply_all_rounded,
                  label: 'Reply all',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(replyTo: item, replyAll: true),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MailActionButton(
                  icon: Icons.forward_rounded,
                  label: 'Forward',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(forward: item),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MailActionButton extends StatelessWidget {
  const _MailActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF3C4043),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        side: const BorderSide(color: Color(0xFFDADCE0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6A7075),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
