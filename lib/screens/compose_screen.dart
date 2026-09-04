import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../branding.dart';
import '../mail_store.dart';
import '../models.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.replyTo, this.forward});
  final MailMessage? replyTo;
  final MailMessage? forward;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;
  bool _showCc = false;

  @override
  void initState() {
    super.initState();
    final reply = widget.replyTo;
    final forward = widget.forward;
    if (reply != null) {
      _to.text = _extractAddress(reply.replyTo.isNotEmpty ? reply.replyTo : reply.from);
      _subject.text = reply.subject.toLowerCase().startsWith('re:') ? reply.subject : 'Re: ${reply.subject}';
      _body.text = '''

--- Original message ---
From: ${reply.from}
Date: ${reply.date}

${reply.bodyText.isEmpty ? reply.snippet : reply.bodyText}''';
    } else if (forward != null) {
      _subject.text = forward.subject.toLowerCase().startsWith('fwd:') ? forward.subject : 'Fwd: ${forward.subject}';
      _body.text = '''

--- Forwarded message ---
From: ${forward.from}
To: ${forward.to}
Date: ${forward.date}
Subject: ${forward.subject}

${forward.bodyText.isEmpty ? forward.snippet : forward.bodyText}''';
    }
  }

  String _extractAddress(String value) {
    final match = RegExp(r'<([^>]+)>').firstMatch(value);
    return (match?.group(1) ?? value).trim();
  }

  List<String> _addresses(String value) => value
      .split(RegExp(r'[,;]'))
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toList();

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _addresses(_to.text);
    if (to.isEmpty || to.any((item) => !item.contains('@'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one valid recipient.')));
      return;
    }
    setState(() => _sending = true);
    try {
      final reply = widget.replyTo;
      await context.read<MailStore>().api.send(
            to: to,
            cc: _addresses(_cc.text),
            subject: _subject.text.trim(),
            bodyText: _body.text,
            inReplyTo: reply?.messageId ?? '',
            references: reply == null ? '' : '${reply.references} ${reply.messageId}'.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent')));
      context.read<MailStore>().refresh();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveDraft() async {
    try {
      await context.read<MailStore>().api.saveDraft(
            to: _addresses(_to.text),
            cc: _addresses(_cc.text),
            subject: _subject.text.trim(),
            bodyText: _body.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft saved')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New message', style: TextStyle(fontWeight: FontWeight.w800, color: imailGreen)),
        actions: [
          IconButton(onPressed: _sending ? null : _saveDraft, tooltip: 'Save draft', icon: const Icon(Icons.drafts_outlined)),
          IconButton(onPressed: _sending ? null : _send, tooltip: 'Send', icon: const Icon(Icons.send_rounded, color: imailGreen)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                TextField(
                  controller: _to,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'To',
                    suffixIcon: IconButton(
                      tooltip: 'Cc',
                      onPressed: () => setState(() => _showCc = !_showCc),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ),
                if (_showCc) ...[
                  const SizedBox(height: 10),
                  TextField(controller: _cc, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Cc')),
                ],
                const SizedBox(height: 10),
                TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject')),
                const SizedBox(height: 14),
                TextField(
                  controller: _body,
                  minLines: 14,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'Write your message…',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: FilledButton.icon(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.send_rounded),
          label: Text(_sending ? 'Sending…' : 'Send message'),
        ),
      ),
    );
  }
}
