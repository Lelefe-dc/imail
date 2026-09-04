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
  bool _quoteExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final message = await context.read<MailStore>().openMessage(widget.seed);
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _name(String value) {
    final lt = value.indexOf('<');
    final raw = lt > 0 ? value.substring(0, lt) : value.split('@').first;
    final clean = raw.replaceAll('"', '').trim();
    return clean.isEmpty ? value : clean;
  }

  String _address(String value) {
    final angle = RegExp(r'<([^>]+)>').firstMatch(value);
    if (angle != null) return angle.group(1)!.trim();
    final email = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).firstMatch(value);
    return email?.group(0) ?? value.trim();
  }

  String _initial(String value) {
    final name = _name(value).trim();
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

  Set<String> _addresses(String value) => RegExp(
        r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
        caseSensitive: false,
      )
          .allMatches(value)
          .map((match) => match.group(0)!.toLowerCase())
          .toSet();

  String _recipientText(MailMessage item, MailStore store) {
    final own = (store.address ?? '').trim().toLowerCase();
    final recipients = <String>{..._addresses(item.to), ..._addresses(item.cc)};
    if (own.isNotEmpty && recipients.contains(own)) return 'to me';
    if (recipients.isEmpty) return 'recipient details';
    if (recipients.length == 1) return 'to ${recipients.first}';
    return 'to ${recipients.first} +${recipients.length - 1}';
  }

  String _date(String raw) {
    if (raw.trim().isEmpty) return '';
    DateTime? value;
    try {
      value = DateTime.parse(raw).toLocal();
    } catch (_) {
      for (final pattern in <String>[
        'EEE, dd MMM yyyy HH:mm:ss Z',
        'EEE, d MMM yyyy HH:mm:ss Z',
      ]) {
        try {
          value = DateFormat(pattern).parse(raw, true).toLocal();
          break;
        } catch (_) {}
      }
    }
    if (value == null) return raw;
    final now = DateTime.now();
    final today = value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    if (today) return DateFormat('HH:mm').format(value);
    if (value.year == now.year) return DateFormat('d MMM, HH:mm').format(value);
    return DateFormat('d MMM yyyy, HH:mm').format(value);
  }

  _BodyParts _bodyParts(MailMessage item) {
    final source = (item.bodyText.isEmpty ? item.snippet : item.bodyText)
        .replaceAll('\r\n', '\n')
        .trimRight();
    if (source.isEmpty) return const _BodyParts('', '');
    final lines = source.split('\n');
    var quoteStart = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('>') ||
          (line.toLowerCase().startsWith('on ') &&
              line.toLowerCase().endsWith('wrote:')) ||
          line == '--- Original message ---' ||
          line == '---------- Forwarded message ----------' ||
          line == '-----Original Message-----') {
        quoteStart = i;
        break;
      }
    }
    if (quoteStart < 0) return _BodyParts(source.trim(), '');
    if (quoteStart == 0) return _BodyParts('', source.trim());
    return _BodyParts(
      lines.take(quoteStart).join('\n').trim(),
      lines.skip(quoteStart).join('\n').trim(),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _star(MailMessage item) async {
    try {
      await context.read<MailStore>().toggleStar(item);
      if (mounted) setState(() => _message = item.copyWith(flagged: !item.flagged));
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _archive(MailMessage item) async {
    try {
      final store = context.read<MailStore>();
      final archive = store.folders.where((f) => f.name.toLowerCase() == 'archive');
      if (archive.isEmpty) {
        _toast('Archive folder is not available for this mailbox.');
        return;
      }
      await store.move(item, archive.first.name);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _delete(MailMessage item) async {
    try {
      await context.read<MailStore>().delete(item);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _markUnread(MailMessage item) async {
    try {
      await context.read<MailStore>().markUnread(item);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _move(MailMessage item, String destination) async {
    try {
      await context.read<MailStore>().move(item, destination);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _download(MailMessage item, MailAttachment attachment) async {
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
      _toast('Saved ${attachment.filename}');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not save the attachment.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _details(MailMessage item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Message details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _DetailRow(label: 'From', value: item.from),
              _DetailRow(label: 'To', value: item.to),
              if (item.cc.isNotEmpty) _DetailRow(label: 'Cc', value: item.cc),
              if (item.replyTo.isNotEmpty)
                _DetailRow(label: 'Reply-to', value: item.replyTo),
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
    final body = _bodyParts(item);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
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
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComposeScreen(replyTo: item),
                ));
              } else if (value == 'reply-all') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComposeScreen(replyTo: item, replyAll: true),
                ));
              } else if (value == 'forward') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComposeScreen(forward: item),
                ));
              } else if (value.startsWith('move:')) {
                _move(item, value.substring(5));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reply', child: Text('Reply')),
              const PopupMenuItem(value: 'reply-all', child: Text('Reply all')),
              const PopupMenuItem(value: 'forward', child: Text('Forward')),
              if (store.folders.where((f) => f.name != store.selectedFolder).isNotEmpty)
                const PopupMenuDivider(),
              ...store.folders
                  .where((folder) => folder.name != store.selectedFolder)
                  .take(10)
                  .map((folder) => PopupMenuItem(
                        value: 'move:${folder.name}',
                        child: Text('Move to ${folder.name}'),
                      )),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 122),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.subject.isEmpty ? '(no subject)' : item.subject,
                        style: const TextStyle(
                          fontSize: 25,
                          height: 1.22,
                          letterSpacing: -0.3,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF202124),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: item.flagged ? 'Unstar' : 'Star',
                      onPressed: () => _star(item),
                      icon: Icon(
                        item.flagged ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 30,
                        color: item.flagged ? imailGold : const Color(0xFF5F6368),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: const Color(0xFFDB4437),
                      child: Text(
                        _initial(item.from),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        onTap: () => _details(item),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _name(item.from),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF202124),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      '<${_address(item.from)}>',
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
                                  Flexible(
                                    child: Text(
                                      _recipientText(item, store),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        color: Color(0xFF5F6368),
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 19,
                                    color: Color(0xFF5F6368),
                                  ),
                                ],
                              ),
                              if (item.date.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  _date(item.date),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF70757A),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Reply',
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ComposeScreen(replyTo: item),
                      )),
                      icon: const Icon(
                        Icons.reply_rounded,
                        size: 27,
                        color: Color(0xFF5F6368),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                if (_message == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  if (body.current.isNotEmpty)
                    SelectableText(
                      body.current,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.62,
                        color: Color(0xFF202124),
                      ),
                    ),
                  if (body.quoted.isNotEmpty) ...[
                    SizedBox(height: body.current.isEmpty ? 0 : 22),
                    if (!_quoteExpanded)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () => setState(() => _quoteExpanded = true),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F3F4),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Text(
                              '•••',
                              style: TextStyle(
                                fontSize: 18,
                                height: 1,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF70757A),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(13, 8, 8, 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Color(0xFFDADCE0), width: 3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                tooltip: 'Hide quoted text',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => _quoteExpanded = false),
                                icon: const Icon(
                                  Icons.expand_less_rounded,
                                  size: 20,
                                  color: Color(0xFF70757A),
                                ),
                              ),
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
                ],
                if (item.attachments.isNotEmpty) ...[
                  const SizedBox(height: 34),
                  const Divider(height: 1, color: Color(0xFFE8EAED)),
                  const SizedBox(height: 18),
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
                        .map((attachment) => InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _downloading ? null : () => _download(item, attachment),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 270),
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
                            ))
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
                child: _ActionButton(
                  icon: Icons.reply_rounded,
                  label: 'Reply',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ComposeScreen(replyTo: item),
                  )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.reply_all_rounded,
                  label: 'Reply all',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ComposeScreen(replyTo: item, replyAll: true),
                  )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.forward_rounded,
                  label: 'Forward',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ComposeScreen(forward: item),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
        backgroundColor: Colors.white,
        minimumSize: const Size.fromHeight(72),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        side: const BorderSide(color: Color(0xFFDADCE0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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

class _BodyParts {
  const _BodyParts(this.current, this.quoted);

  final String current;
  final String quoted;
}
