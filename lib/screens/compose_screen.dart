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
      _to.text = _extractAddress(
        reply.replyTo.isNotEmpty ? reply.replyTo : reply.from,
      );
      _subject.text = reply.subject.toLowerCase().startsWith('re:')
          ? reply.subject
          : 'Re: ${reply.subject}';
      _body.text = '''

--- Original message ---
From: ${reply.from}
Date: ${reply.date}

${reply.bodyText.isEmpty ? reply.snippet : reply.bodyText}''';
    } else if (forward != null) {
      _subject.text = forward.subject.toLowerCase().startsWith('fwd:')
          ? forward.subject
          : 'Fwd: ${forward.subject}';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one valid recipient.')),
      );
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
            references: reply == null
                ? ''
                : '${reply.references} ${reply.messageId}'.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent')),
      );
      context.read<MailStore>().refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  InputDecoration _lineDecoration({
    required String label,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF646B70)),
      suffixIcon: suffix,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 4,
        title: const Text(
          'New message',
          style: TextStyle(
            color: Color(0xFF262A2E),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Save draft',
            onPressed: _sending ? null : _saveDraft,
            icon: const Icon(Icons.drafts_outlined),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, color: imailGreen),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_sending)
            const LinearProgressIndicator(
              minHeight: 2,
              color: imailEmerald,
            ),
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: _to,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: _lineDecoration(
                    label: 'To',
                    suffix: IconButton(
                      tooltip: 'Show Cc',
                      onPressed: () => setState(() => _showCc = !_showCc),
                      icon: Icon(
                        _showCc
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
                if (_showCc) ...[
                  TextField(
                    controller: _cc,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: _lineDecoration(label: 'Cc'),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                ],
                TextField(
                  controller: _subject,
                  textInputAction: TextInputAction.next,
                  decoration: _lineDecoration(label: 'Subject'),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
                Expanded(
                  child: TextField(
                    controller: _body,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'Compose email',
                      hintStyle: TextStyle(color: Color(0xFF7B8185)),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(20, 20, 20, 28),
                    ),
                    style: const TextStyle(fontSize: 16, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
