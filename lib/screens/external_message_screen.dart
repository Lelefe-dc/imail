import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../branding.dart';
import 'external_compose_screen.dart';

class ExternalMessageScreen extends StatefulWidget {
  const ExternalMessageScreen({
    super.key,
    required this.client,
    required this.account,
    required this.message,
    required this.mailbox,
  });

  final MailClient client;
  final MailAccount account;
  final MimeMessage message;
  final Mailbox? mailbox;

  @override
  State<ExternalMessageScreen> createState() => _ExternalMessageScreenState();
}

class _ExternalMessageScreenState extends State<ExternalMessageScreen> {
  bool _quoteExpanded = false;
  bool _busy = false;

  String _name(MimeMessage message) {
    final values = message.from ?? message.envelope?.from;
    if (values != null && values.isNotEmpty) {
      final first = values.first;
      return first.hasPersonalName ? first.personalName! : first.email;
    }
    return message.fromEmail ?? 'Unknown sender';
  }

  String _email(MimeMessage message) {
    final values = message.from ?? message.envelope?.from;
    if (values != null && values.isNotEmpty) return values.first.email;
    return message.fromEmail ?? '';
  }

  String _to(MimeMessage message) {
    final values = message.to ?? message.envelope?.to ?? const <MailAddress>[];
    if (values.isEmpty) return '';
    return values.map((item) => item.email).join(', ');
  }

  String _subject(MimeMessage message) =>
      message.decodeSubject() ?? message.envelope?.subject ?? '(no subject)';

  String _date(MimeMessage message) {
    final value = message.decodeDate() ?? message.envelope?.date;
    if (value == null) return '';
    return DateFormat('EEE, d MMM yyyy, HH:mm').format(value.toLocal());
  }

  _BodyParts _bodyParts(MimeMessage message) {
    var text = message.decodeTextPlainPart();
    if (text == null || text.trim().isEmpty) {
      final html = message.decodeTextHtmlPart();
      if (html != null) {
        text = html
            .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
            .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');
      }
    }
    final source = (text ?? '').replaceAll('\r\n', '\n').trimRight();
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

  Future<void> _toggleStar() async {
    setState(() => _busy = true);
    try {
      final next = !widget.message.isFlagged;
      await widget.client.flagMessage(widget.message, isFlagged: next);
      widget.message.isFlagged = next;
      if (mounted) setState(() {});
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final boxes = widget.client.mailboxes ?? await widget.client.listMailboxes();
    final archive = boxes.where((box) => box.isArchive).toList();
    if (archive.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This server has no Archive folder.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.moveMessage(widget.message, archive.first);
      if (mounted) Navigator.pop(context);
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await widget.client.deleteMessage(widget.message, expunge: true);
      if (mounted) Navigator.pop(context);
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markUnread() async {
    setState(() => _busy = true);
    try {
      await widget.client.flagMessage(widget.message, isSeen: false);
      widget.message.isSeen = false;
      if (mounted) Navigator.pop(context);
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final body = _bodyParts(message);
    final sender = _name(message);
    final senderEmail = _email(message);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Archive',
            onPressed: _busy ? null : _archive,
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            tooltip: 'Mark unread',
            onPressed: _busy ? null : _markUnread,
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _subject(message),
                  style: const TextStyle(
                    fontSize: 25,
                    height: 1.22,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF202124),
                  ),
                ),
              ),
              IconButton(
                tooltip: message.isFlagged ? 'Unstar' : 'Star',
                onPressed: _busy ? null : _toggleStar,
                icon: Icon(
                  message.isFlagged ? Icons.star_rounded : Icons.star_border_rounded,
                  color: message.isFlagged ? imailGold : const Color(0xFF5F6368),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: const Color(0xFFDB4437),
                child: Text(
                  sender.isEmpty ? '?' : sender.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '<$senderEmail>',
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
                    Text(
                      _to(message).isEmpty ? 'recipient details' : 'to ${_to(message)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF5F6368),
                      ),
                    ),
                    if (_date(message).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _date(message),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF70757A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reply',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExternalComposeScreen(
                      client: widget.client,
                      account: widget.account,
                      replyTo: message,
                    ),
                  ),
                ),
                icon: const Icon(Icons.reply_rounded),
              ),
            ],
          ),
          const SizedBox(height: 34),
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
                        onPressed: () => setState(() => _quoteExpanded = false),
                        icon: const Icon(Icons.expand_less_rounded),
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExternalComposeScreen(
                        client: widget.client,
                        account: widget.account,
                        replyTo: message,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.reply_all_rounded,
                  label: 'Reply all',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExternalComposeScreen(
                        client: widget.client,
                        account: widget.account,
                        replyTo: message,
                        replyAll: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.forward_rounded,
                  label: 'Forward',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExternalComposeScreen(
                        client: widget.client,
                        account: widget.account,
                        forward: message,
                      ),
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

class _BodyParts {
  const _BodyParts(this.current, this.quoted);

  final String current;
  final String quoted;
}
