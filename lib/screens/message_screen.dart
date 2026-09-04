import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  bool _showQuotedText = false;

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

  Color _avatarColor(String seed) {
    const palette = <Color>[
      Color(0xFFEA4335),
      Color(0xFF4285F4),
      Color(0xFF34A853),
      Color(0xFFFBBC04),
      Color(0xFF7E57C2),
      Color(0xFF00897B),
    ];
    return palette[seed.toLowerCase().hashCode.abs() % palette.length];
  }

  String _formatDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    DateTime? date;
    try {
      date = DateTime.parse(value).toLocal();
    } catch (_) {
      for (final pattern in <String>[
        'EEE, dd MMM yyyy HH:mm:ss Z',
        'EEE, d MMM yyyy HH:mm:ss Z',
      ]) {
        try {
          date = DateFormat(pattern).parse(value, true).toLocal();
          break;
        } catch (_) {}
      }
    }
    if (date == null) return value;
    return DateFormat('EEE, d MMM, HH:mm').format(date);
  }

  String _recipientSummary(MailMessage item, MailStore store) {
    final own = (store.address ?? '').trim().toLowerCase();
    final recipientEmails = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).allMatches(item.to).map((match) => match.group(0)!.toLowerCase()).toList();
    if (own.isNotEmpty && recipientEmails.contains(own)) return 'to me';
    if (item.to.trim().isEmpty) return 'recipient details';
    return 'to ${item.to}';
  }

  _BodyParts _bodyParts(MailMessage item) {
    final value = (item.bodyText.isEmpty ? item.snippet : item.bodyText)
        .replaceAll('\r\n', '\n')
        .trimRight();
    if (value.isEmpty) return const _BodyParts('', '');

    final lines = value.split('\n');
    var quoteStart = -1;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('>') ||
          RegExp(r'^On .+ wrote:$', caseSensitive: false).hasMatch(trimmed) ||
          trimmed == '---------- Forwarded message ----------' ||
          trimmed == '--- Original message ---' ||
          trimmed == '-----Original Message-----') {
        quoteStart = i;
        break;
      }
    }

    if (quoteStart <= 0) return _BodyParts(value.trim(), '');
    return _BodyParts(
      lines.take(quoteStart).join('\n').trim(),
      lines.skip(quoteStart).join('\n').trim(),
    );
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
              if (item.replyTo.isNotEmpty)
                _DetailRow(label: 'Reply-to', value: item.replyTo),
              if (item.date.isNotEmpty)
                _DetailRow(label: 'Date', value: _formatDate(item.date)),
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
    final body = _bodyParts(item);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FC),
        surfaceTintColor: const Color(0xFFF3F6FC),
        elevation: 0,
        scrolledUnderElevation: 0,
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 122),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.subject.isEmpty ? '(no subject)' : item.subject,
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1.22,
                            letterSpacing: -0.25,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF202124),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0B000000),
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: _avatarColor(item.from),
                              child: Text(
                                _senderInitial(item.from),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _showRecipientDetails(item),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1),
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
                                          Flexible(
                                            child: Text(
                                              '<${_senderAddress(item.from)}>',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF5F6368),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _recipientSummary(item, store),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF5F6368),
                                              ),
                                            ),
                                          ),
                                          if (item.date.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatDate(item.date),
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF70757A),
                                              ),
                                            ),
                                          ],
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
                              icon: const Icon(
                                Icons.reply_rounded,
                                size: 25,
                                color: Color(0xFF5F6368),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF0F1F3)),
                      if (_message == null)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 44),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (body.current.isNotEmpty)
                                SelectableText(
                                  body.current,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.65,
                                    color: Color(0xFF202124),
                                  ),
                                ),
                              if (body.quoted.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                if (!_showQuotedText)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => setState(() => _showQuotedText = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFD),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFE2E7F0),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '•••',
                                            style: TextStyle(
                                              color: Color(0xFF6F757A),
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Show quoted text',
                                            style: TextStyle(
                                              color: Color(0xFF5F6368),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFD),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE2E7F0),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 3,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFCAD3E2),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Expanded(
                                                    child: Text(
                                                      'Quoted conversation',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF6F757A),
                                                      ),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    visualDensity: VisualDensity.compact,
                                                    tooltip: 'Collapse quoted text',
                                                    onPressed: () => setState(
                                                      () => _showQuotedText = false,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.expand_less_rounded,
                                                      size: 21,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SelectableText(
                                                body.quoted,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  height: 1.55,
                                                  color: Color(0xFF5F6368),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (item.attachments.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.attachments.length} attachment${item.attachments.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF202124),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: item.attachments
                              .map(
                                (attachment) => InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: _downloading
                                      ? null
                                      : () => _downloadAttachment(item, attachment),
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 270),
                                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFD),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFE0E5EC),
                                      ),
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
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFF3F6FC),
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

class _BodyParts {
  const _BodyParts(this.current, this.quoted);

  final String current;
  final String quoted;
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
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3C4043),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        side: const BorderSide(color: Color(0xFFD6DCE6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
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
            width: 62,
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
