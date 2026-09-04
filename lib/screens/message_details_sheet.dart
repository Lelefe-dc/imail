import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

Future<void> showMessageDetailsSheet(
  BuildContext context,
  MailMessage item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x73000000),
    builder: (context) => _MessageDetailsSheet(item: item),
  );
}

class _MessageDetailsSheet extends StatelessWidget {
  const _MessageDetailsSheet({required this.item});

  final MailMessage item;

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

  String _formatDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    DateTime? parsed;
    try {
      parsed = DateTime.parse(value).toLocal();
    } catch (_) {
      for (final pattern in <String>[
        'EEE, dd MMM yyyy HH:mm:ss Z',
        'EEE, d MMM yyyy HH:mm:ss Z',
      ]) {
        try {
          parsed = DateFormat(pattern).parse(value, true).toLocal();
          break;
        } catch (_) {}
      }
    }

    if (parsed == null) return value;
    return DateFormat('EEE, d MMM yyyy, HH:mm').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final senderName = _name(item.from);
    final senderAddress = _address(item.from);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFBDC1C6),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Message details',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: Color(0xFF202124),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EAED)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFEA4335),
                        child: Text(
                          senderName.isEmpty
                              ? '?'
                              : senderName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF202124),
                              ),
                            ),
                            if (senderAddress.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              SelectableText(
                                senderAddress,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF5F6368),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _DetailRow(
                    icon: Icons.person_outline_rounded,
                    label: 'From',
                    value: item.from,
                  ),
                  _DetailRow(
                    icon: Icons.call_made_rounded,
                    label: 'To',
                    value: item.to,
                  ),
                  if (item.cc.trim().isNotEmpty)
                    _DetailRow(
                      icon: Icons.people_outline_rounded,
                      label: 'Cc',
                      value: item.cc,
                    ),
                  if (item.replyTo.trim().isNotEmpty)
                    _DetailRow(
                      icon: Icons.reply_rounded,
                      label: 'Reply-to',
                      value: item.replyTo,
                    ),
                  if (item.date.trim().isNotEmpty)
                    _DetailRow(
                      icon: Icons.schedule_rounded,
                      label: 'Date',
                      value: _formatDate(item.date),
                    ),
                  if (item.subject.trim().isNotEmpty)
                    _DetailRow(
                      icon: Icons.subject_rounded,
                      label: 'Subject',
                      value: item.subject,
                      last: true,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFF0F1F3)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF5F6368),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 66,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6F757A),
                ),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Color(0xFF202124),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
