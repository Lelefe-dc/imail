class MailAttachment {
  const MailAttachment({
    required this.index,
    required this.filename,
    required this.contentType,
    required this.size,
  });

  final int index;
  final String filename;
  final String contentType;
  final int size;

  factory MailAttachment.fromJson(Map<String, dynamic> json) => MailAttachment(
        index: (json['index'] as num?)?.toInt() ?? 0,
        filename: json['filename']?.toString() ?? 'attachment',
        contentType:
            json['content_type']?.toString() ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class MailUploadAttachment {
  const MailUploadAttachment({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String filename;
  final String contentType;
  final List<int> bytes;

  int get size => bytes.length;
}

class MailMessage {
  const MailMessage({
    required this.uid,
    required this.from,
    required this.to,
    required this.cc,
    required this.subject,
    required this.date,
    required this.snippet,
    required this.seen,
    required this.flagged,
    required this.answered,
    required this.draft,
    required this.attachments,
    this.bodyText = '',
    this.messageId = '',
    this.inReplyTo = '',
    this.references = '',
    this.replyTo = '',
  });

  final String uid;
  final String from;
  final String to;
  final String cc;
  final String replyTo;
  final String subject;
  final String date;
  final String snippet;
  final bool seen;
  final bool flagged;
  final bool answered;
  final bool draft;
  final String bodyText;
  final String messageId;
  final String inReplyTo;
  final String references;
  final List<MailAttachment> attachments;

  factory MailMessage.fromJson(Map<String, dynamic> json) => MailMessage(
        uid: json['uid']?.toString() ?? '',
        from: json['from']?.toString() ?? '',
        to: json['to']?.toString() ?? '',
        cc: json['cc']?.toString() ?? '',
        replyTo: json['reply_to']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '(no subject)',
        date: json['date']?.toString() ?? '',
        snippet: json['snippet']?.toString() ?? '',
        seen: json['seen'] == true,
        flagged: json['flagged'] == true,
        answered: json['answered'] == true,
        draft: json['draft'] == true,
        bodyText: json['body_text']?.toString() ?? '',
        messageId: json['message_id']?.toString() ?? '',
        inReplyTo: json['in_reply_to']?.toString() ?? '',
        references: json['references']?.toString() ?? '',
        attachments: ((json['attachments'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  MailAttachment.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );

  MailMessage copyWith({bool? seen, bool? flagged, bool? answered}) =>
      MailMessage(
        uid: uid,
        from: from,
        to: to,
        cc: cc,
        replyTo: replyTo,
        subject: subject,
        date: date,
        snippet: snippet,
        seen: seen ?? this.seen,
        flagged: flagged ?? this.flagged,
        answered: answered ?? this.answered,
        draft: draft,
        bodyText: bodyText,
        messageId: messageId,
        inReplyTo: inReplyTo,
        references: references,
        attachments: attachments,
      );
}

class MailFolder {
  const MailFolder(
    this.name, {
    this.totalCount = 0,
    this.unreadCount = 0,
  });

  final String name;
  final int totalCount;
  final int unreadCount;

  /// Gmail-like drawer semantics: folders whose important number is unread
  /// show unread, while Sent/Drafts/Trash show the real number of messages.
  int get count {
    final lower = name.toLowerCase();
    if (lower == 'inbox' ||
        lower == 'junk' ||
        lower == 'spam' ||
        lower == 'updates' ||
        lower == 'promotions' ||
        lower == 'social') {
      return unreadCount;
    }
    return totalCount;
  }

  MailFolder copyWith({int? totalCount, int? unreadCount}) => MailFolder(
        name,
        totalCount: totalCount ?? this.totalCount,
        unreadCount: unreadCount ?? this.unreadCount,
      );

  String get fingerprint => '$name:$totalCount:$unreadCount';
}
