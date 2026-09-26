import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kheja_link/widgets/social_links.dart';

void main() {
  testWidgets('shows TikTok and WhatsApp with their logos, and nothing else', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Padding(padding: EdgeInsets.all(20), child: SocialLinks())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('@kheja_link'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('+254 710 655709'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    for (final gone in ['Facebook', 'Instagram', 'Twitter', 'LinkedIn', 'X']) {
      expect(find.text(gone), findsNothing);
    }
    expect(tester.takeException(), isNull, reason: 'the logos parse and draw');
  });

  test('links point at the real channels', () {
    expect(KhejaSocial.tiktokUrl, 'https://www.tiktok.com/@kheja_link');
    expect(KhejaSocial.whatsappUrl, 'https://wa.me/254710655709');
  });
}
