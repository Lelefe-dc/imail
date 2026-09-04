import 'package:flutter_test/flutter_test.dart';
import 'package:imail/mail_conversation.dart';
import 'package:imail/models.dart';

MailMessage message({
  required String uid,
  required String subject,
  String messageId = '',
  String inReplyTo = '',
  String references = '',
  bool seen = true,
}) =>
    MailMessage(
      uid: uid,
      from: 'sender@example.test',
      to: 'me@example.test',
      cc: '',
      subject: subject,
      date: '2026-09-04T12:00:00Z',
      snippet: subject,
      seen: seen,
      flagged: false,
      answered: false,
      draft: false,
      attachments: const [],
      messageId: messageId,
      inReplyTo: inReplyTo,
      references: references,
    );

void main() {
  test('groups replies using References and Message-ID', () {
    final rows = [
      message(
        uid: '2',
        subject: 'Re: Project',
        messageId: '<reply@example.test>',
        inReplyTo: '<root@example.test>',
        references: '<root@example.test>',
        seen: false,
      ),
      message(
        uid: '1',
        subject: 'Project',
        messageId: '<root@example.test>',
      ),
    ];

    final groups = groupMailConversations(rows);
    expect(groups, hasLength(1));
    expect(groups.first.count, 2);
    expect(groups.first.unread, isTrue);
  });

  test('keeps unrelated messages separate', () {
    final groups = groupMailConversations([
      message(uid: '1', subject: 'One', messageId: '<one@example.test>'),
      message(uid: '2', subject: 'Two', messageId: '<two@example.test>'),
    ]);
    expect(groups, hasLength(2));
  });
}
