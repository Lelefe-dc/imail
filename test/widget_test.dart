import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imail/branding.dart';

void main() {
  testWidgets('iMail logo renders', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: IMailLogo()));
    expect(find.byType(IMailLogo), findsOneWidget);
  });
}
