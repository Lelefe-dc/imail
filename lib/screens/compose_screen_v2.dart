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
  Timer? _autosaveTimer;
  bool _showCcBcc = false;
  bool _sending = false;
  bool _savingDraft = false;
  bool _closing = false;
  bool _restoredLocalDraft = false;
  String _signature = '';
  String _accountAddress = '';

  MailMessage? get _source => widget.forward ?? widget.replyTo;

  String get _draftId {
    final source = _source;
    final key = source?.messageId.isNotEmpty == true
        ? source!.messageId
        : source?.uid ?? 'new';
    return '${_mode.name}-$key';
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.forward != null
        ? _ComposeMode.forward
        : widget.replyTo != null
            ? (widget.replyAll ? _ComposeMode.replyAll : _ComposeMode.reply)
            : _ComposeMode.newMessage;
    _setSubject();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.addListener(_scheduleAutosave);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.removeListener(_scheduleAutosave);
      controller.dispose();
    }
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final store = context.read<MailStore>();
    _accountAddress = store.address ?? '';
    _configureRecipients(store);
    try {
      final signature = await _accountApi.signature();
      if (mounted) setState(() => _signature = _plainText(signature));
    } catch (_) {}

    if (_accountAddress.isNotEmpty) {
      final local = await _draftStore.load(_accountAddress, _draftId);
      if (local != null && !local.isEmpty && mounted) {
        setState(() {
          _to.text = local.to;
          _cc.text = local.cc;
          _bcc.text = local.bcc;
          _subject.text = local.subject;
          _body.text = local.body;
          _showCcBcc = local.cc.isNotEmpty || local.bcc.isNotEmpty;
          _restoredLocalDraft = true;
        });
      }
    }
    if (mounted) _bodyFocus.requestFocus();
  }

  void _scheduleAutosave() {
    if (_closing || _sending) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 850), () {
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
    if (_accountAddress.isEmpty) return;
    await _draftStore.save(_accountAddress, _draftId, _snapshot());
  }

  Future<void> _clearLocal() async {
    if (_accountAddress.isEmpty) return;
    await _draftStore.clear(_accountAddress, _draftId);
  }

  String _plainText(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  String _extractAddress(String value) {
    final angle = RegExp(r'<([^>]+)>').firstMatch(value);
    if (angle != null) return angle.group(1)!.trim().toLowerCase();
    final emails = _emailAddresses(value);
    return emails.isEmpty ? value.trim().toLowerCase() : emails.first;
  }

  List<String> _emailAddresses(String value) {
    final matches = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).allMatches(value);
    final rows = <String>[];
    for (final match in matches) {
      final email = match.group(0)!.toLowerCase();
      if (!rows.contains(email)) rows.add(email);
    }
    return rows;
  }

  List<String> _addresses(String value) {
    final parsed = _emailAddresses(value);
    if (parsed.isNotEmpty) return parsed;
    return value
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.contains('@'))
        .toSet()
        .toList(growable: false);
  }

  void _setSubject() {
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

  void _configureRecipients(MailStore store) {
    final source = _source;
    if (source == null || _restoredLocalDraft) return;
    if (_mode == _ComposeMode.forward) return;

    final sender = _extractAddress(
      source.replyTo.isNotEmpty ? source.replyTo : source.from,
    );
    _to.text = sender;
    if (_mode == _ComposeMode.replyAll) {
      final own = (store.address ?? '').toLowerCase();
      final others = <String>[
        ..._emailAddresses(source.to),
        ..._emailAddresses(source.cc),
      ].where((email) => email != own && email != sender).toSet().toList();
      _cc.text = others.join(', ');
      _showCcBcc = others.isNotEmpty;
    }
  }

  String _quoteForSend() {
    final source = _source;
    if (source == null) return '';
    final body = source.bodyText.isEmpty ? source.snippet : source.bodyText;
    if (_mode == _ComposeMode.forward) {
      return '''

---------- Forwarded message ----------
From: ${source.from}
Date: ${source.date}
Subject: ${source.subject}
To: ${source.to}${source.cc.isEmpty ? '' : '\nCc: ${source.cc}'}

$body''';
    }
    final quoted = body
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
    return '''

On ${source.date}, ${source.from} wrote:
$quoted''';
  }

  String _bodyForSend() {
    final parts = <String>[_body.text.trimRight()];
    if (_signature.trim().isNotEmpty) {
      parts.add('\n-- \n${_signature.trim()}');
    }
    final quote = _quoteForSend();
    if (quote.isNotEmpty) parts.add(quote);
    return parts.join();
  }

  String _contentTypeFor(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.txt')) return 'text/plain';
    if (name.endsWith('.csv')) return 'text/csv';
    if (name.endsWith('.zip')) return 'application/zip';
    if (name.endsWith('.doc')) return 'application/msword';
    if (name.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (name.endsWith('.xls')) return 'application/vnd.ms-excel';
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

    const maxBytes = 15 * 1024 * 1024;
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
      if (bytes == null || bytes.length > maxBytes) {
        skipped++;
        continue;
      }
      added.add(
        MailUploadAttachment(
          filename: file.name,
          contentType: _contentTypeFor(file.name),
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
    final to = _addresses(_to.text);
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
      await store.api.send(
        to: to,
        cc: _addresses(_cc.text),
        bcc: _addresses(_bcc.text),
        subject: _subject.text.trim(),
        bodyText: _bodyForSend(),
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
      for (final address in {...to, ..._addresses(_cc.text), ..._addresses(_bcc.text)}) {
        unawaited(_accountApi.saveContact(address));
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

  Future<void> _saveServerDraft({bool close = true}) async {
    if (_savingDraft) return;
    setState(() => _savingDraft = true);
    try {
      await context.read<MailStore>().api.saveDraft(
        to: _addresses(_to.text),
        cc: _addresses(_cc.text),
        subject: _subject.text.trim(),
        bodyText: _bodyForSend(),
      );
      await _clearLocal();
      if (!mounted) return;
      if (_bcc.text.trim().isNotEmpty || _attachments.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft saved. Bcc and attachments remain protected in the local autosave until full server draft persistence is available.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
      }
      if (close) {
        _closing = true;
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (_closing) return true;
    await _saveLocal();
    return true;
  }

  Future<void> _discard() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this message?'),
        content: const Text('The local autosave and this unsent message will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Discard')),
        ],
      ),
    );
    if (confirm != true) return;
    await _clearLocal();
    if (!mounted) return;
    _closing = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
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
                PopupMenuItem(value: 'save', child: Text('Save draft to server')),
                PopupMenuItem(value: 'discard', child: Text('Discard')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
          children: [
            if (_restoredLocalDraft)
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
                    Expanded(child: Text('Your local autosaved draft was restored.')),
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
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E9E7))),
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
                  style: const TextStyle(color: Color(0xFF6D756F), fontSize: 13.5),
                ),
              ),
            if (_attachments.isNotEmpty) ...[
              const Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _attachments.length; i++)
                    InputChip(
                      avatar: const Icon(Icons.attach_file_rounded, size: 17),
                      label: Text(_attachments[i].filename),
                      onDeleted: _sending
                          ? null
                          : () => setState(() => _attachments.removeAt(i)),
                    ),
                ],
              ),
            ],
            if (_savingDraft)
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
  void didUpdateWidget(covariant _RecipientField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  String _token() {
    final value = widget.controller.text;
    final pieces = value.split(RegExp(r'[,;]'));
    return pieces.isEmpty ? value.trim() : pieces.last.trim();
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
    final value = widget.controller.text;
    final match = RegExp(r'^(.*[,;]\s*)?[^,;]*$').firstMatch(value);
    final prefix = match?.group(1) ?? '';
    final display = contact.name.trim().isEmpty
        ? contact.email
        : '${contact.name.trim()} <${contact.email}>';
    widget.controller.text = '$prefix$display, ';
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
                          (contact.name.isNotEmpty ? contact.name : contact.email)[0].toUpperCase(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                      title: Text(contact.name.isEmpty ? contact.email : contact.name),
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
