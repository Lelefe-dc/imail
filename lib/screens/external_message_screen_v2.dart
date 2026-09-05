import 'dart:async';

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
  late MimeMessage _message;
  bool _loadingBody = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    unawaited(_loadFullMessage());
  }

  Future<void> _loadFullMessage() async {
    if (mounted) {
      setState(() {
        _loadingBody = true;
        _loadError = null;
      });
    }
    try {
      final full = await widget.client
          .fetchMessageContents(widget.message, markAsSeen: true)
          .timeout(const Duration(seconds: 12));
      widget.message.isSeen = true;
      if (!mounted) return;
      setState(() {
        _message = full;
        _loadingBody = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loadingBody = false;
        _loadError = 'Message content took too long to load. Tap Retry.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBody = false;
        _loadError = 'Message content could not be loaded. Tap Retry.';
      });
    }
  }

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
    return values.map((item) => item.email).join(', ');
  }

  String _subject(MimeMessage message) =>
      message.decodeSubject() ?? message.envelope?.subject ?? '(no subject)';

  String _date(MimeMessage message) {
    final value = message.decodeDate() ?? message.envelope?.date;
    if (value == null) return '';
    return DateFormat('EEE, d MMM yyyy, HH:mm').format(value.toLocal());
  }

  String _body(MimeMessage message) {
    final plain = message.decodeTextPlainPart();
    if (plain != null && plain.trim().isNotEmpty) {
      return plain.replaceAll('\r\n', '\n').trim();
    }
    final html = message.decodeTextHtmlPart();
    if (html == null || html.trim().isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<void> _toggleStar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = !_message.isFlagged;
      await widget.client.flagMessage(_message, isFlagged: next);
      _message.isFlagged = next;
      widget.message.isFlagged = next;
      if (mounted) setState(() {});
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteMessage(_message, expunge: true);
      if (mounted) Navigator.pop(context, true);
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markUnread() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.flagMessage(_message, isSeen: false);
      widget.message.isSeen = false;
      if (mounted) Navigator.pop(context, true);
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reply({bool all = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExternalComposeScreen(
          client: widget.client,
          account: widget.account,
          replyTo: _message,
          replyAll: all,
        ),
      ),
    );
  }

  void _forward() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExternalComposeScreen(
          client: widget.client,
          account: widget.account,
          forward: _message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(_message);
    final sender = _name(_message);
    final senderEmail = _email(_message);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: _message.isFlagged ? 'Unstar' : 'Star',
            onPressed: _busy ? null : _toggleStar,
            icon: Icon(
              _message.isFlagged ? Icons.star_rounded : Icons.star_border_rounded,
              color: _message.isFlagged ? imailGold : const Color(0xFF5F6368),
            ),
          ),
          IconButton(
            tooltip: 'Mark unread',
            onPressed: _busy ? null : _markUnread,
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
        children: [
          Text(
            _subject(_message),
            style: const TextStyle(
              fontSize: 25,
              height: 1.22,
              fontWeight: FontWeight.w600,
              color: Color(0xFF202124),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: imailGreen,
                foregroundColor: Colors.white,
                child: Text(
                  sender.isEmpty ? '?' : sender.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    if (senderEmail.isNotEmpty)
                      Text(
                        senderEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF667085), fontSize: 13),
                      ),
                    if (_to(_message).isNotEmpty)
                      Text(
                        'to ${_to(_message)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF667085), fontSize: 13),
                      ),
                    if (_date(_message).isNotEmpty)
                      Text(
                        _date(_message),
                        style: const TextStyle(color: Color(0xFF8A9299), fontSize: 12),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reply',
                onPressed: () => _reply(),
                icon: const Icon(Icons.reply_rounded),
              ),
            ],
          ),
          const SizedBox(height: 30),
          if (_loadingBody)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (body.isNotEmpty)
            SelectableText(
              body,
              style: const TextStyle(fontSize: 16, height: 1.62, color: Color(0xFF202124)),
            )
          else
            Material(
              color: const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      _loadError ?? 'This message has no readable text content.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF667085)),
                    ),
                    if (_loadError != null) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _loadFullMessage,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _reply(),
                  icon: const Icon(Icons.reply_rounded),
                  label: const Text('Reply'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _reply(all: true),
                  icon: const Icon(Icons.reply_all_rounded),
                  label: const Text('Reply all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _forward,
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
