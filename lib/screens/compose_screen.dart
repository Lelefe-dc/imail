import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../branding.dart';
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

  final List<MailUploadAttachment> _attachments = [];

  late _ComposeMode _mode;
  bool _showCcBcc = false;
  bool _quoteExpanded = false;
  bool _sending = false;
  bool _savingDraft = false;
  bool _closing = false;

  MailMessage? get _source => widget.forward ?? widget.replyTo;

  @override
  void initState() {
    super.initState();
    _mode = widget.forward != null
        ? _ComposeMode.forward
        : widget.replyTo != null
            ? (widget.replyAll ? _ComposeMode.replyAll : _ComposeMode.reply)
            : _ComposeMode.newMessage;
    _setSubjectForMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureRecipients();
      if (_mode != _ComposeMode.newMessage) {
        _bodyFocus.requestFocus();
      }
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

  String _extractAddress(String value) {
    final match = RegExp(r'<([^>]+)>').firstMatch(value);
    if (match != null) return match.group(1)!.trim().toLowerCase();
    final emails = _emailAddresses(value);
    return emails.isEmpty ? value.trim().toLowerCase() : emails.first;
  }

  List<String> _emailAddresses(String value) {
    final matches = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).allMatches(value);
    final values = <String>[];
    for (final match in matches) {
      final email = match.group(0)!.toLowerCase();
      if (!values.contains(email)) values.add(email);
    }
    return values;
  }

  List<String> _addresses(String value) {
    final parsed = _emailAddresses(value);
    if (parsed.isNotEmpty) return parsed;
    final values = value
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
    return values.toSet().toList();
  }

  void _setSubjectForMode() {
    final source = _source;
    if (source == null) return;
    final subject = source.subject == '(no subject)' ? '' : source.subject;
    if (_mode == _ComposeMode.forward) {
      _subject.text = subject.toLowerCase().startsWith('fwd:')
          ? subject
          : 'Fwd: $subject';
    } else if (_mode == _ComposeMode.reply || _mode == _ComposeMode.replyAll) {
      _subject.text = subject.toLowerCase().startsWith('re:')
          ? subject
          : 'Re: $subject';
    }
  }

  void _configureRecipients() {
    final source = _source;
    if (source == null) return;

    if (_mode == _ComposeMode.forward) {
      _to.clear();
      _cc.clear();
      _bcc.clear();
      setState(() => _showCcBcc = false);
      return;
    }

    final sender = _extractAddress(
      source.replyTo.isNotEmpty ? source.replyTo : source.from,
    );
    _to.text = sender;
    _cc.clear();

    if (_mode == _ComposeMode.replyAll) {
      final own = (context.read<MailStore>().address ?? '').toLowerCase();
      final others = <String>[
        ..._emailAddresses(source.to),
        ..._emailAddresses(source.cc),
      ]
          .where((email) => email != own && email != sender)
          .toSet()
          .toList();
      _cc.text = others.join(', ');
      setState(() => _showCcBcc = others.isNotEmpty);
    } else {
      setState(() => _showCcBcc = false);
    }
  }

  void _changeMode(_ComposeMode value) {
    if (value == _mode) return;
    setState(() {
      _mode = value;
      _quoteExpanded = false;
    });
    _setSubjectForMode();
    _configureRecipients();
    _bodyFocus.requestFocus();
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
    if (name.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (name.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
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

    const maxBytesPerFile = 18 * 1024 * 1024;
    var skipped = 0;
    final added = <MailUploadAttachment>[];

    for (final file in result.files) {
      if (_attachments.length + added.length >= 20) {
        skipped++;
        continue;
      }
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null || bytes.length > maxBytesPerFile) {
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
        SnackBar(
          content: Text(
            '$skipped attachment${skipped == 1 ? '' : 's'} could not be added. Files must be under 18 MB and there is a 20-file limit.',
          ),
        ),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
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

  bool get _hasDraftContent =>
      _to.text.trim().isNotEmpty ||
      _cc.text.trim().isNotEmpty ||
      _bcc.text.trim().isNotEmpty ||
      _subject.text.trim().isNotEmpty ||
      _body.text.trim().isNotEmpty ||
      _attachments.isNotEmpty;

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
      final source = _source;
      final bodyText = '${_body.text.trimRight()}${_quoteForSend()}';
      await context.read<MailStore>().api.send(
            to: to,
            cc: _addresses(_cc.text),
            bcc: _addresses(_bcc.text),
            subject: _subject.text.trim(),
            bodyText: bodyText,
            attachments: _attachments,
            inReplyTo: _mode == _ComposeMode.reply ||
                    _mode == _ComposeMode.replyAll
                ? source?.messageId ?? ''
                : '',
            references: _mode == _ComposeMode.reply ||
                    _mode == _ComposeMode.replyAll
                ? '${source?.references ?? ''} ${source?.messageId ?? ''}'.trim()
                : '',
          );
      if (source != null &&
          (_mode == _ComposeMode.reply || _mode == _ComposeMode.replyAll)) {
        await context.read<MailStore>().markAnswered(source);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      _closing = true;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Message sent')));
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

  Future<void> _saveDraft({bool close = true}) async {
    if (_savingDraft || !_hasDraftContent) {
      if (close && mounted) {
        _closing = true;
        Navigator.pop(context);
      }
      return;
    }
    setState(() => _savingDraft = true);
    try {
      await context.read<MailStore>().api.saveDraft(
            to: _addresses(_to.text),
            cc: _addresses(_cc.text),
            subject: _subject.text.trim(),
            bodyText: '${_body.text.trimRight()}${_quoteForSend()}',
          );
      if (!mounted) return;
      if (_attachments.isNotEmpty || _bcc.text.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Draft saved. The current server draft format does not yet persist Bcc or attachments.',
            ),
          ),
        );
      }
      if (close) {
        _closing = true;
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _closeComposer() async {
    if (_closing || _sending) return;
    if (!_hasDraftContent) {
      _closing = true;
      Navigator.pop(context);
      return;
    }
    await _saveDraft();
  }

  Future<void> _discard() async {
    if (!_hasDraftContent) {
      _closing = true;
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text('This message will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _closing = true;
      Navigator.pop(context);
    }
  }

  InputDecoration _plainDecoration({String? hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 15),
    );
  }

  Widget _fromRow(MailStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 13, 18, 13),
      child: Row(
        children: [
          const SizedBox(
            width: 64,
            child: Text(
              'From',
              style: TextStyle(fontSize: 16, color: Color(0xFF5F6368)),
            ),
          ),
          Expanded(
            child: Text(
              store.address ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Color(0xFF202124)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressField({
    required String label,
    required TextEditingController controller,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 10, 0),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Color(0xFF5F6368)),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: _plainDecoration(suffix: suffix),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyRecipientRow() {
    final source = _source!;
    final address = _extractAddress(
      source.replyTo.isNotEmpty ? source.replyTo : source.from,
    );
    final icon = _mode == _ComposeMode.replyAll
        ? Icons.reply_all_rounded
        : Icons.reply_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
      child: Row(
        children: [
          PopupMenuButton<_ComposeMode>(
            tooltip: 'Reply options',
            onSelected: _changeMode,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ComposeMode.reply,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.reply_rounded),
                  title: Text('Reply'),
                ),
              ),
              PopupMenuItem(
                value: _ComposeMode.replyAll,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.reply_all_rounded),
                  title: Text('Reply all'),
                ),
              ),
              PopupMenuItem(
                value: _ComposeMode.forward,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.forward_rounded),
                  title: Text('Forward'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 30, color: const Color(0xFF5F6368)),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 23,
                    color: Color(0xFF5F6368),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF9AA0A6)),
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.fromLTRB(4, 3, 13, 3),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFDB4437),
                    foregroundColor: Colors.white,
                    child: Text(
                      address.isEmpty ? '?' : address[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF202124),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cc and Bcc',
            onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
            icon: Icon(
              _showCcBcc
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 29,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subjectRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: _subject,
        textInputAction: TextInputAction.next,
        decoration: _plainDecoration(hint: 'Subject'),
        style: const TextStyle(fontSize: 17, color: Color(0xFF202124)),
      ),
    );
  }

  Widget _attachmentStrip() {
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8F9FA),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _attachments.length; i++)
            Container(
              constraints: const BoxConstraints(maxWidth: 250),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFDADCE0)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 19),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _attachments[i].filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          _formatSize(_attachments[i].size),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF6D7479),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove attachment',
                    onPressed: _sending
                        ? null
                        : () => setState(() => _attachments.removeAt(i)),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _quotePreview() {
    final source = _source;
    if (source == null) return const SizedBox.shrink();
    final body = source.bodyText.isEmpty ? source.snippet : source.bodyText;
    if (!_quoteExpanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => _quoteExpanded = true),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Text(
              '•••',
              style: TextStyle(
                color: Color(0xFF74787B),
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
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
          Row(
            children: [
              Expanded(
                child: Text(
                  _mode == _ComposeMode.forward
                      ? 'Forwarded message from ${source.from}'
                      : 'On ${source.date}, ${source.from} wrote:',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6F757A),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _quoteExpanded = false),
                icon: const Icon(Icons.expand_less_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF6F757A),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    final replying = _mode == _ComposeMode.reply || _mode == _ComposeMode.replyAll;

    return WillPopScope(
      onWillPop: () async {
        if (_sending) return false;
        if (_hasDraftContent) await _saveDraft(close: false);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _closeComposer,
            icon: const Icon(Icons.arrow_back_rounded, size: 30),
          ),
          title: _mode == _ComposeMode.newMessage
              ? const Text(
                  'Compose',
                  style: TextStyle(
                    color: Color(0xFF202124),
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Attach file',
              onPressed: _sending ? null : _pickAttachments,
              icon: const Icon(Icons.attach_file_rounded, size: 29),
            ),
            IconButton(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: const Icon(
                Icons.send_rounded,
                color: Color(0xFF0B57D0),
                size: 31,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'save') _saveDraft();
                if (value == 'discard') _discard();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'save', child: Text('Save draft')),
                PopupMenuItem(value: 'discard', child: Text('Discard')),
              ],
              icon: const Icon(Icons.more_vert_rounded, size: 29),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            if (_sending || _savingDraft)
              const LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFF0B57D0),
              ),
            _fromRow(store),
            const Divider(height: 1),
            if (replying)
              _replyRecipientRow()
            else
              _addressField(
                label: 'To',
                controller: _to,
                suffix: IconButton(
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
              _addressField(label: 'Cc', controller: _cc),
              const Divider(height: 1),
              _addressField(label: 'Bcc', controller: _bcc),
            ],
            const Divider(height: 1),
            _subjectRow(),
            const Divider(height: 1),
            _attachmentStrip(),
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
                        hintStyle: TextStyle(color: Color(0xFF80868B)),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 12),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Color(0xFF202124),
                      ),
                    ),
                  ),
                  _quotePreview(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
