import 'dart:async';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../branding.dart';
import 'external_compose_screen.dart';
import 'external_message_screen.dart';

class ExternalMailboxScreen extends StatefulWidget {
  const ExternalMailboxScreen({super.key, required this.account});

  final MailAccount account;

  @override
  State<ExternalMailboxScreen> createState() => _ExternalMailboxScreenState();
}

class _ExternalMailboxScreenState extends State<ExternalMailboxScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();

  MailClient? _client;
  StreamSubscription<MailLoadEvent>? _incomingSubscription;
  List<Mailbox> _mailboxes = const [];
  List<MimeMessage> _messages = const [];
  Mailbox? _selected;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    _search.dispose();
    _incomingSubscription?.cancel();
    final client = _client;
    if (client != null) unawaited(_closeClient(client));
    super.dispose();
  }

  Future<void> _closeClient(MailClient client) async {
    try {
      await client.stopPollingIfNeeded();
    } catch (_) {}
    try {
      await client.disconnect();
    } catch (_) {}
  }

  Future<void> _connect() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final old = _client;
      if (old != null) await _closeClient(old);
      await _incomingSubscription?.cancel();

      final client = MailClient(
        widget.account,
        isLogEnabled: false,
        defaultResponseTimeout: const Duration(seconds: 10),
      );
      await client.connect(timeout: const Duration(seconds: 15));
      final boxes = await client.listMailboxes();
      final inboxes = boxes.where((box) => box.isInbox).toList();
      final inbox = inboxes.isNotEmpty
          ? inboxes.first
          : await client.selectInbox();
      if (inboxes.isNotEmpty) await client.selectMailbox(inbox);

      _client = client;
      _mailboxes = boxes;
      _selected = inbox;
      _incomingSubscription = client.eventBus.on<MailLoadEvent>().listen((_) {
        if (mounted) unawaited(_refresh(silent: true));
      });
      await client.startPolling(const Duration(seconds: 20));
      await _loadSelected();
    } on MailException catch (e) {
      if (mounted) setState(() => _error = 'Could not open this mailbox.\n$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open this mailbox.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSelected() async {
    final client = _client;
    final mailbox = _selected;
    if (client == null || mailbox == null) return;
    await client.selectMailbox(mailbox);
    final items = await client
        .fetchMessages(
          mailbox: mailbox,
          count: 50,
          fetchPreference: FetchPreference.fullWhenWithinSize,
        )
        .timeout(const Duration(seconds: 15));
    if (!mounted) return;
    setState(() {
      _messages = items;
      _error = null;
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _busy = true);
    try {
      await _loadSelected();
    } catch (e) {
      if (!silent && mounted) setState(() => _error = '$e');
    } finally {
      if (!silent && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(Mailbox mailbox) async {
    Navigator.maybePop(context);
    if (!mounted) return;
    setState(() {
      _selected = mailbox;
      _messages = const [];
      _busy = true;
      _search.clear();
    });
    try {
      await _loadSelected();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sender(MimeMessage item) {
    final from = item.from ?? item.envelope?.from;
    if (from != null && from.isNotEmpty) {
      final first = from.first;
      return first.hasPersonalName ? first.personalName! : first.email;
    }
    return item.fromEmail ?? 'Unknown sender';
  }

  String _subject(MimeMessage item) =>
      item.decodeSubject() ?? item.envelope?.subject ?? '(no subject)';

  String _snippet(MimeMessage item) {
    var text = item.decodeTextPlainPart() ?? '';
    if (text.trim().isEmpty) {
      text = (item.decodeTextHtmlPart() ?? '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ');
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _date(MimeMessage item) {
    final date = item.decodeDate() ?? item.envelope?.date;
    if (date == null) return '';
    final value = date.toLocal();
    final now = DateTime.now();
    if (value.year == now.year && value.month == now.month && value.day == now.day) {
      return DateFormat.Hm().format(value);
    }
    if (value.year == now.year) return DateFormat.MMMd().format(value);
    return DateFormat.yMd().format(value);
  }

  List<MimeMessage> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages.where((item) {
      return '${_sender(item)} ${_subject(item)} ${_snippet(item)}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  Future<void> _star(MimeMessage item) async {
    final client = _client;
    if (client == null) return;
    final next = !item.isFlagged;
    try {
      await client.flagMessage(item, isFlagged: next);
      item.isFlagged = next;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _open(MimeMessage item) async {
    final client = _client;
    if (client == null || !mounted) return;

    // Open the reader immediately. Some IMAP servers are slow when fetching a
    // complete MIME body; waiting here made a tapped row look unresponsive.
    // The reader fetches the full body itself with a timeout and Retry action.
    if (!item.isSeen) {
      item.isSeen = true;
      setState(() {});
      unawaited(
        client.flagMessage(item, isSeen: true).catchError((_) {}),
      );
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExternalMessageScreen(
          client: client,
          account: widget.account,
          message: item,
          mailbox: _selected,
        ),
      ),
    );
    if (mounted) unawaited(_refresh(silent: true));
  }

  IconData _folderIcon(Mailbox box) {
    if (box.isInbox) return Icons.inbox_rounded;
    if (box.isDrafts) return Icons.drafts_outlined;
    if (box.isArchive) return Icons.archive_outlined;
    final value = box.name.toLowerCase();
    if (value.contains('sent')) return Icons.send_rounded;
    if (value.contains('trash') || value.contains('deleted')) {
      return Icons.delete_outline_rounded;
    }
    if (value.contains('spam') || value.contains('junk')) {
      return Icons.report_outlined;
    }
    return Icons.folder_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF3F6FC),
      drawer: Drawer(
        backgroundColor: Colors.white,
        width: MediaQuery.sizeOf(context).width * 0.84,
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 16, 22, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IMailLogo(width: 190),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.account.email,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  children: [
                    for (final box in _mailboxes)
                      ListTile(
                        selected: _selected?.path == box.path,
                        selectedTileColor: const Color(0xFFE1F0E8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        leading: Icon(_folderIcon(box)),
                        title: Text(
                          box.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _select(box),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Mail folders',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu_rounded, size: 31),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SearchBar(
                      controller: _search,
                      hintText: 'Search in mail',
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor: const WidgetStatePropertyAll(Colors.white),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: imailGreen,
                    foregroundColor: Colors.white,
                    child: Text(widget.account.email.substring(0, 1).toUpperCase()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 22, 24, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _selected?.isInbox == true ? 'Primary' : (_selected?.name ?? 'Mail'),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF30343A),
                  ),
                ),
              ),
            ),
            if (_busy)
              const LinearProgressIndicator(
                minHeight: 2,
                color: imailEmerald,
                backgroundColor: Colors.transparent,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Material(
                  color: const Color(0xFFFFF4F2),
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_error!),
                    trailing: TextButton(onPressed: _connect, child: const Text('Retry')),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: imailGreen,
                onRefresh: _refresh,
                child: items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 110),
                          Icon(Icons.mark_email_read_outlined, size: 64, color: Color(0xFF98A2B3)),
                          SizedBox(height: 14),
                          Text('No messages here', textAlign: TextAlign.center),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final sender = _sender(item);
                          return Material(
                            color: item.isSeen ? Colors.white : const Color(0xFFF0F7F3),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _open(item),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: item.isSeen
                                          ? const Color(0xFFE5ECE8)
                                          : imailGreen,
                                      foregroundColor: item.isSeen ? imailGreen : Colors.white,
                                      child: Text(
                                        sender.isEmpty ? '?' : sender.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  sender,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: item.isSeen ? FontWeight.w600 : FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              Text(_date(item), style: const TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _subject(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: item.isSeen ? FontWeight.w500 : FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _snippet(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Color(0xFF667085)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: item.isFlagged ? 'Unstar' : 'Star',
                                      onPressed: () => _star(item),
                                      icon: Icon(
                                        item.isFlagged ? Icons.star_rounded : Icons.star_border_rounded,
                                        color: item.isFlagged ? imailGold : const Color(0xFF667085),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'external-compose',
        backgroundColor: const Color(0xFFDFF3E9),
        foregroundColor: imailGreen,
        onPressed: _client == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExternalComposeScreen(
                      client: _client!,
                      account: widget.account,
                    ),
                  ),
                ),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Compose'),
      ),
    );
  }
}
