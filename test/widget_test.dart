import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imail/branding.dart';
import 'package:imail/models.dart';

void main() {
  testWidgets('iMail logo renders', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IMailLogo(),
      ),
    );
    expect(find.byType(IMailLogo), findsOneWidget);
  });

  test('folder counters use total for Sent and unread for Inbox', () {
    const inbox = MailFolder('INBOX', totalCount: 12, unreadCount: 3);
    const sent = MailFolder('Sent', totalCount: 1, unreadCount: 0);
    const trash = MailFolder('Trash', totalCount: 2, unreadCount: 0);

    expect(inbox.count, 3);
    expect(sent.count, 1);
    expect(trash.count, 2);
  });
}
