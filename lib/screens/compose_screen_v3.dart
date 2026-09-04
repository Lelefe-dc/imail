import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../branding.dart';
import '../compose_draft_store.dart';
import '../mail_account_api.dart';
import '../mail_store.dart';
import '../models.dart';

enum _ComposeMode { newMessage, reply, replyAll, forward }

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    this.replyTo,
    this.forward,
    this.replyAll = false,
  });

  final MailMessage? replyTo;
  final MailMessage? forward;
  final bool replyAll;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  final _accountApi = MailAccountApi();
  final _draftStore = ComposeDraftStore();
  final List<MailUploadAttachment> _attachments = [];

  late final _ComposeMode _mode;
  Timer? _autosave;
  bool _showCcBcc = false;
  bool _sending = false;
  bool _saving = false;
  bool _closing = false;
  bool _restored = false;
  String _signature = '';
  String _account = '';

  MailMessage? get _source => widget.forward ?? widget.replyTo;
  String get _draftId {
    final source = _source;
    final sourceKey = source?.messageId.isNotEmpty == true
        ? source!.messageId
        : source?.uid ?? 'new';
    return '${_mode.name}-$sourceKey';
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.forward != null
        ? _ComposeMode.forward
        : widget.replyTo != null
            ? (widget.replyAll ? _ComposeMode.replyAll : _ComposeMode.reply)
            : _ComposeMode.newMessage;
    _prepareSubject();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.addListener(_queueAutosave);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.removeListener(_queueAutosave);
      controller.dispose();
    }
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final store = context.read<MailStore>();
    _account = store.address ?? '';
    _prepareRecipients(store);

    try {
      final signature = await _accountApi.signature();
      if (mounted) setState(() => _signature = _plain(signature));
    } catch (_) {}

    if (_account.isNotEmpty) {
      final snapshot = await _draftStore.load(_account, _draftId);
      if (snapshot != null && !snapshot.isEmpty && mounted) {
        setState(() {
          _to.text = snapshot.to;
          _cc.text = snapshot.cc;
          _bcc.text = snapshot.bcc;
          _subject.text = snapshot.subject;
          _body.text = snapshot.body;
          _showCcBcc = snapshot.cc.isNotEmpty || snapshot.bcc.isNotEmpty;
          _restored = true;
        });
      }
    }
    if (mounted) _bodyFocus.requestFocus();
  }

  String _plain(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  void _queueAutosave() {
    if (_closing || _sending) return;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), () {
      unawaited(_saveLocal());
    });
  }

  ComposeDraftSnapshot _snapshot() => ComposeDraftSnapshot(
        to: _to.text,
        cc: _cc.text,
        bcc: _bcc.text,
        subject: _subject.text,
        body: _body.text,
      );

  Future<void> _saveLocal() async {
    if (_account.isEmpty) return;
    await _draftStore.save(_account, _draftId, _snapshot());
  }

  Future<void> _clearLocal() async {
    if (_account.isEmpty) return;
    await _draftStore.clear(_account, _draftId);
  }

  List<String> _emails(String value) {
    final matches = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).allMatches(value);
    return matches
        .map((match) => match.group(0)!.toLowerCase())
        .toSet()
        .toList(growable: false);
  }

  String _address(String value) {
    final angle = RegExp(r'<([^>]+)>').firstMatch(value);
    if (angle != null) return angle.group(1)!.trim().toLowerCase();
    final addresses = _emails(value);
    return addresses.isEmpty ? value.trim().toLowerCase() : addresses.first;
  }

  void _prepareSubject() {
    final source = _source;
    if (source == null) return;
    final subject = source.subject == '(no subject)' ? '' : source.subject;
    if (_mode == _ComposeMode.forward) {
      _subject.text = subject.toLowerCase().startsWith('fwd:')
          ? subject
          : 'Fwd: $subject';
    } else {
      _subject.text = subject.toLowerCase().startsWith('re:')
          ? subject
          : 'Re: $subject';
    }
  }

  void _prepareRecipients(MailStore store) {
    final source = _source;
    if (source == null || _mode == _ComposeMode.forward) return;
    final sender = _address(
      source.replyTo.isNotEmpty ? source.replyTo : source.from,
    );
    _to.text = sender;
    if (_mode != _ComposeMode.replyAll) return;
    final own = (store.address ?? '').toLowerCase();
    final others = <String>{..._emails(source.to), ..._emails(source.cc)}
      ..remove(own)
      ..remove(sender);
    _cc.text = others.join(', ');
    _showCcBcc = others.isNotEmpty;
  }

  String _quote() {
    final source = _source;
    if (source == null) return '';
    final sourceBody = source.bodyText.isEmpty ? source.snippet : source.bodyText;
    if (_mode == _ComposeMode.forward) {
      return '''

---------- Forwarded message ----------
From: ${source.from}
Date: ${source.date}
Subject: ${source.subject}
To: ${source.to}${source.cc.isEmpty ? '' : '\nCc: ${source.cc}'}

$sourceBody''';
    }
    final quoted = sourceBody
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
    return '\n\nOn ${source.date}, ${source.from} wrote:\n$quoted';
  }

  String _sendBody() {
    final buffer = StringBuffer(_body.text.trimRight());
    if (_signature.isNotEmpty) buffer.write('\n\n-- \n${_signature.trim()}');
    buffer.write(_quote());
    return buffer.toString();
  }

  String _contentType(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.txt')) return 'text/plain';
    if (name.endsWith('.csv')) return 'text/csv';
    if (name.endsWith('.zip')) return 'application/zip';
    if (name.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (name.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  Future<void> _pickAttachments() async {
    if (_sending || _attachments.length >= 20) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    const maxSingle = 15 * 1024 * 1024;
    final added = <MailUploadAttachment>[];
    var skipped = 0;
    for (final file in result.files) {
      if (_attachments.length + added.length >= 20) {
        skipped++;
        continue;
      }
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes == null || bytes.length > maxSingle) {
        skipped++;
        continue;
      }
      added.add(
        MailUploadAttachment(
          filename: file.name,
          contentType: _contentType(file.name),
          bytes: bytes,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _attachments.addAll(added));
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$skipped attachment${skipped == 1 ? '' : 's'} could not be added.')),
      );
    }
  }

  Future<void> _send() async {
    final to = _emails(_to.text);
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one valid recipient.')),
      );
      return;
    }
    final store = context.read<MailStore>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final source = _source;
      final cc = _emails(_cc.text);
      final bcc = _emails(_bcc.text);
      await store.api.send(
        to: to,
        cc: cc,
        bcc: bcc,
        subject: _subject.text.trim(),
        bodyText: _sendBody(),
        attachments: _attachments,
        inReplyTo: _mode == _ComposeMode.reply || _mode == _ComposeMode.replyAll
            ? source?.messageId ?? ''
            : '',
        references: _mode == _ComposeMode.reply || _mode == _ComposeMode.replyAll
            ? '${source?.references ?? ''} ${source?.messageId ?? ''}'.trim()
            : '',
      );
      if (source != null &&
          (_mode == _ComposeMode.reply || _mode == _ComposeMode.replyAll)) {
        await store.markAnswered(source);
      }
      for (final recipient in {...to, ...cc, ...bcc}) {
        unawaited(_accountApi.saveContact(recipient));
      }
      await _clearLocal();
      if (!mounted) return;
      _closing = true;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Message sent')));
      unawaited(store.refresh());
    } on ApiException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveServerDraft() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await _accountApi.saveFullDraft(
        to: _emails(_to.text),
        cc: _emails(_cc.text),
        bcc: _emails(_bcc.text),
        subject: _subject.text.trim(),
        bodyText: _sendBody(),
        attachments: _attachments,
      );
      await _clearLocal();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Draft saved')));
      _closing = true;
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _canPop() async {
    if (_closing) return true;
    await _saveLocal();
    return true;
  }

  Future<void> _discard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this message?'),
        content: const Text('The autosaved copy will also be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    await _clearLocal();
    if (!mounted) return;
    _closing = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _canPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text(
            _mode == _ComposeMode.newMessage
                ? 'New message'
                : _mode == _ComposeMode.forward
                    ? 'Forward'
                    : _mode == _ComposeMode.replyAll
                        ? 'Reply all'
                        : 'Reply',
          ),
          leading: IconButton(
            tooltip: 'Save and close',
            onPressed: () async {
              await _saveLocal();
              if (!mounted) return;
              _closing = true;
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            IconButton(
              tooltip: 'Attach files',
              onPressed: _sending ? null : _pickAttachments,
              icon: const Icon(Icons.attach_file_rounded),
            ),
            IconButton(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: imailGreen),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'save') unawaited(_saveServerDraft());
                if (value == 'discard') unawaited(_discard());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'save', child: Text('Save draft')),
                PopupMenuItem(value: 'discard', child: Text('Discard')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
          children: [
            if (_restored)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4EF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.restore_rounded, size: 18, color: imailGreen),
                    SizedBox(width: 8),
                    Expanded(child: Text('Your autosaved draft was restored.')),
                  ],
                ),
              ),
            _RecipientField(
              label: 'To',
              controller: _to,
              api: _accountApi,
              trailing: IconButton(
                tooltip: 'Cc/Bcc',
                onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
            if (_showCcBcc) ...[
              _RecipientField(label: 'Cc', controller: _cc, api: _accountApi),
              _RecipientField(label: 'Bcc', controller: _bcc, api: _accountApi),
            ],
            TextField(
              controller: _subject,
              decoration: const InputDecoration(
                hintText: 'Subject',
                filled: false,
                border: UnderlineInputBorder(),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFE5E9E7)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              focusNode: _bodyFocus,
              minLines: 12,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Write a message',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            if (_signature.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Text(
                  '-- \n$_signature',
                  style: const TextStyle(
                    color: Color(0xFF6D756F),
                    fontSize: 13.5,
                  ),
                ),
              ),
            if (_attachments.isNotEmpty) ...[
              const Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _attachments.length; index++)
                    InputChip(
                      avatar: const Icon(Icons.attach_file_rounded, size: 17),
                      label: Text(_attachments[index].filename),
                      onDeleted: _sending
                          ? null
                          : () => setState(() => _attachments.removeAt(index)),
                    ),
                ],
              ),
            ],
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecipientField extends StatefulWidget {
  const _RecipientField({
    required this.label,
    required this.controller,
    required this.api,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final MailAccountApi api;
  final Widget? trailing;

  @override
  State<_RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<_RecipientField> {
  Timer? _debounce;
  List<MailContact> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  String _token() {
    final parts = widget.controller.text.split(RegExp(r'[,;]'));
    return parts.isEmpty ? '' : parts.last.trim();
  }

  void _changed() {
    _debounce?.cancel();
    final token = _token();
    if (token.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        final rows = await widget.api.contacts(token);
        if (mounted && token == _token()) {
          setState(() => _suggestions = rows.take(5).toList(growable: false));
        }
      } catch (_) {
        if (mounted) setState(() => _suggestions = const []);
      }
    });
  }

  void _choose(MailContact contact) {
    final text = widget.controller.text;
    final separator = text.lastIndexOf(RegExp(r'[,;]'));
    final prefix = separator < 0 ? '' : text.substring(0, separator + 1).trimRight();
    final display = contact.name.trim().isEmpty
        ? contact.email
        : '${contact.name.trim()} <${contact.email}>';
    widget.controller.text = prefix.isEmpty ? '$display, ' : '$prefix $display, ';
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            prefixText: '${widget.label}:  ',
            suffixIcon: widget.trailing,
            filled: false,
            border: const UnderlineInputBorder(),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE5E9E7)),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Material(
            color: const Color(0xFFF7FAF8),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: _suggestions
                  .map(
                    (contact) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFE0EFE8),
                        foregroundColor: imailGreen,
                        child: Text(
                          (contact.name.isNotEmpty ? contact.name : contact.email)[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        contact.name.isEmpty ? contact.email : contact.name,
                      ),
                      subtitle: contact.name.isEmpty ? null : Text(contact.email),
                      onTap: () => _choose(contact),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}
