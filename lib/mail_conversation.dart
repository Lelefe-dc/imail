import 'models.dart';

class MailConversation {
  const MailConversation({required this.key, required this.messages});

  final String key;
  final List<MailMessage> messages;

  MailMessage get latest => messages.first;
  int get count => messages.length;
  bool get unread => messages.any((message) => !message.seen);
  bool get flagged => messages.any((message) => message.flagged);

  Set<String> get uids => messages.map((message) => message.uid).toSet();
}

List<MailConversation> groupMailConversations(List<MailMessage> messages) {
  if (messages.isEmpty) return const [];

  final byMessageId = <String, MailMessage>{};
  for (final message in messages) {
    final id = _cleanId(message.messageId);
    if (id.isNotEmpty) byMessageId[id] = message;
  }

  String rootFor(MailMessage message) {
    final refs = _ids(message.references);
    if (refs.isNotEmpty) return 'id:${refs.first}';

    final parent = _cleanId(message.inReplyTo);
    if (parent.isNotEmpty) {
      final loadedParent = byMessageId[parent];
      if (loadedParent != null) {
        final parentRefs = _ids(loadedParent.references);
        if (parentRefs.isNotEmpty) return 'id:${parentRefs.first}';
        final parentParent = _cleanId(loadedParent.inReplyTo);
        if (parentParent.isNotEmpty) return 'id:$parentParent';
      }
      return 'id:$parent';
    }

    final own = _cleanId(message.messageId);
    if (own.isNotEmpty) return 'id:$own';
    return 'subject:${_normalizedSubject(message.subject)}';
  }

  final groups = <String, List<MailMessage>>{};
  final order = <String>[];
  for (final message in messages) {
    var key = rootFor(message);

    // If this looks like a reply without References but an original with the
    // same normalized subject is already loaded, keep the visible thread
    // together. Message-ID based grouping still has priority when available.
    final subjectKey = 'subject:${_normalizedSubject(message.subject)}';
    if (!groups.containsKey(key) &&
        (message.inReplyTo.isNotEmpty ||
            message.subject.trim().toLowerCase().startsWith('re:'))) {
      final subjectGroup = order.where((existing) {
        final group = groups[existing];
        if (group == null || group.isEmpty) return false;
        return 'subject:${_normalizedSubject(group.first.subject)}' == subjectKey;
      }).cast<String?>().firstWhere((value) => value != null, orElse: () => null);
      if (subjectGroup != null) key = subjectGroup;
    }

    if (!groups.containsKey(key)) {
      groups[key] = <MailMessage>[];
      order.add(key);
    }
    groups[key]!.add(message);
  }

  return order
      .map(
        (key) => MailConversation(
          key: key,
          messages: List<MailMessage>.unmodifiable(groups[key]!),
        ),
      )
      .toList(growable: false);
}

List<String> _ids(String value) => RegExp(r'<[^>]+>')
    .allMatches(value)
    .map((match) => _cleanId(match.group(0) ?? ''))
    .where((value) => value.isNotEmpty)
    .toList(growable: false);

String _cleanId(String value) =>
    value.trim().replaceAll(RegExp(r'^<|>$'), '').toLowerCase();

String _normalizedSubject(String value) {
  var subject = value.trim().toLowerCase();
  while (true) {
    final next = subject.replaceFirst(
      RegExp(r'^(re|fw|fwd)\s*:\s*', caseSensitive: false),
      '',
    );
    if (next == subject) break;
    subject = next.trim();
  }
  return subject.isEmpty ? '(no subject)' : subject;
}
