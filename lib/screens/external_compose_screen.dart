import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ExternalComposeScreen extends StatefulWidget {
  const ExternalComposeScreen({
    super.key,
    required this.client,
    required this.account,
    this.replyTo,
    this.forward,
    this.replyAll = false,
  });

  final MailClient client;
  final MailAccount account;
  final MimeMessage? replyTo;
  final MimeMessage? forward;
  final bool replyAll;

  @override
  State<ExternalComposeScreen> createState() => _ExternalComposeScreenState();
}

class _ExternalComposeScreenState extends State<ExternalComposeScreen> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  final List<_PickedAttachment> _attachments = [];

  bool _showCcBcc = false;
  bool _sending = false;
  bool _quoteExpanded = false;

  @override
  void initState() {
    super.initState();
    _seed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _bcc.dispose();
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  List<MailAddress> _addressesOf(MimeMessage message, String group) {
    switch (group) {
      case 'from':
        return message.from ?? message.envelope?.from ?? const [];
      case 'to':
        return message.to ?? message.envelope?.to ?? const [];
      case 'cc':
        return message.cc ?? message.envelope?.cc ?? const [];
      case 'replyTo':
        return message.replyTo ?? message.envelope?.replyTo ?? const [];
      default:
        return const [];
    }
  }

  String _subjectOf(MimeMessage message) =>
      message.decodeSubject() ?? message.envelope?.subject ?? '';

  String _plainBody(MimeMessage message) {
    final plain = message.decodeTextPlainPart();
    if (plain != null && plain.trim().isNotEmpty) return plain;
    final html = message.decodeTextHtmlPart();
    if (html == null) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  void _seed() {
    final reply = widget.replyTo;
    if (reply != null) {
      final replyAddresses = _addressesOf(reply, 'replyTo');
      final senders = replyAddresses.isNotEmpty
          ? replyAddresses
          : _addressesOf(reply, 'from');
      if (senders.isNotEmpty) _to.text = senders.first.email;

      if (widget.replyAll) {
        final own = widget.account.email.toLowerCase();
        final target = _to.text.toLowerCase();
        final others = <String>{};
        for (final address in [
          ..._addressesOf(reply, 'to'),
          ..._addressesOf(reply, 'cc'),
        ]) {
          final email = address.email.toLowerCase();
          if (email != own && email != target) others.add(address.email);
        }
        if (others.isNotEmpty) {
          _cc.text = others.join(', ');
          _showCcBcc = true;
        }
      }
      final subject = _subjectOf(reply);
      _subject.text = subject.toLowerCase().startsWith('re:')
          ? subject
          : 'Re: $subject';
      return;
    }

    final forward = widget.forward;
    if (forward != null) {
      final subject = _subjectOf(forward);
      _subject.text = subject.toLowerCase().startsWith('fwd:')
          ? subject
          : 'Fwd: $subject';
    }
  }

  List<MailAddress> _parseAddresses(String value) {
    final result = <MailAddress>[];
    for (final token in value.split(RegExp(r'[,;]'))) {
      final text = token.trim();
      if (text.isEmpty) continue;
      try {
        result.add(MailAddress.parse(text));
      } catch (_) {
        if (text.contains('@')) result.add(MailAddress(null, text));
      }
    }
    return result;
  }

  String _quoteText() {
    final source = widget.replyTo ?? widget.forward;
    if (source == null) return '';
    final body = _plainBody(source);
    final from = _addressesOf(source, 'from');
    final fromText = from.isEmpty ? 'Unknown sender' : from.first.encode();
    final date = source.decodeDate()?.toLocal().toString() ?? '';

    if (widget.forward != null) {
      final to = _addressesOf(source, 'to').map((e) => e.encode()).join(', ');
      return '\n\n---------- Forwarded message ----------\n'
          'From: $fromText\n'
          'Date: $date\n'
          'Subject: ${_subjectOf(source)}\n'
          'To: $to\n\n$body';
    }

    final quoted = body
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
    return '\n\nOn $date, $fromText wrote:\n$quoted';
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    const maxFileSize = 18 * 1024 * 1024;
    var skipped = 0;
    final picked = <_PickedAttachment>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.length > maxFileSize) {
        skipped++;
        continue;
      }
      picked.add(_PickedAttachment(file.name, bytes));
    }
    setState(() => _attachments.addAll(picked));
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$skipped attachment(s) could not be added.')),
      );
    }
  }

  Future<void> _send() async {
    final to = _parseAddresses(_to.text);
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one recipient.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final fullText = '${_body.text.trimRight()}${_quoteText()}';
      final builder = MessageBuilder()
        ..from = [widget.account.fromAddress]
        ..to = to
        ..cc = _parseAddresses(_cc.text)
        ..bcc = _parseAddresses(_bcc.text)
        ..subject = _subject.text.trim()
        ..addTextPlain(fullText);

      final reply = widget.replyTo;
      if (reply != null) {
        final messageId = reply.getHeaderValue('Message-ID') ??
            reply.envelope?.messageId ??
            '';
        if (messageId.isNotEmpty) {
          builder.addHeader('In-Reply-To', messageId);
          final previous = reply.getHeaderValue('References') ?? '';
          builder.addHeader(
            'References',
            '$previous $messageId'.trim(),
          );
        }
      }

      for (final attachment in _attachments) {
        builder.addBinary(
          attachment.bytes,
          MediaType.guessFromFileName(attachment.name),
          filename: attachment.name,
        );
      }

      final message = builder.buildMimeMessage();
      await widget.client.sendMessage(message);
      if (reply != null) {
        try {
          await widget.client.flagMessage(reply, isAnswered: true);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent')),
      );
    } on MailException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message.\n$e')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message.\n$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.replyTo ?? widget.forward;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        leading: const BackButton(),
        title: source == null ? const Text('Compose') : null,
        actions: [
          IconButton(
            tooltip: 'Attach file',
            onPressed: _sending ? null : _pickAttachments,
            icon: const Icon(Icons.attach_file_rounded, size: 28),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: const Icon(
              Icons.send_rounded,
              color: Color(0xFF0B57D0),
              size: 30,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_sending)
            const LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFF0B57D0),
            ),
          _line(
            'From',
            Text(
              widget.account.email,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const Divider(height: 1),
          _line(
            'To',
            TextField(
              controller: _to,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            trailing: IconButton(
              tooltip: 'Cc and Bcc',
              onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
              icon: Icon(
                _showCcBcc
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
            ),
          ),
          if (_showCcBcc) ...[
            const Divider(height: 1),
            _line(
              'Cc',
              TextField(
                controller: _cc,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 1),
            _line(
              'Bcc',
              TextField(
                controller: _bcc,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _subject,
              decoration: const InputDecoration(
                hintText: 'Subject',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const Divider(height: 1),
          if (_attachments.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFFF8F9FA),
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _attachments.length; i++)
                    Chip(
                      avatar: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(_attachments[i].name),
                      onDeleted: _sending
                          ? null
                          : () => setState(() => _attachments.removeAt(i)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'Compose email',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 12),
                    ),
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
                if (source != null)
                  if (!_quoteExpanded)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: () => setState(() => _quoteExpanded = true),
                        borderRadius: BorderRadius.circular(18),
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
                          child: Text(
                            '•••',
                            style: TextStyle(
                              fontSize: 21,
                              color: Color(0xFF70757A),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                              onPressed: () =>
                                  setState(() => _quoteExpanded = false),
                              icon: const Icon(Icons.expand_less_rounded),
                            ),
                          ),
                          Text(
                            _quoteText().trim(),
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: Color(0xFF6F757A),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, Widget child, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 10, 0),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF5F6368),
              ),
            ),
          ),
          Expanded(child: child),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _PickedAttachment {
  const _PickedAttachment(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}
