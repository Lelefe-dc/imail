import 'package:flutter/material.dart';

const Color imailGreen = Color(0xFF064A34);
const Color imailEmerald = Color(0xFF0A9E60);
const Color imailGold = Color(0xFFD8AD3D);
const Color imailSurface = Color(0xFFF6F8F7);

class IMailLogo extends StatelessWidget {
  const IMailLogo({super.key, this.width = 260});

  final double width;

  @override
  Widget build(BuildContext context) {
    final iconSize = width * 0.28;
    return Semantics(
      label: 'iMail by Ithute Mail',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: const CustomPaint(painter: _IMailMarkPainter()),
          ),
          SizedBox(width: width * 0.035),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: width * 0.19,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.6,
                  ),
                  children: const [
                    TextSpan(text: 'i', style: TextStyle(color: imailGold)),
                    TextSpan(text: 'Mail', style: TextStyle(color: imailGreen)),
                  ],
                ),
              ),
              SizedBox(height: width * 0.018),
              Text(
                'i t h u t e   m a i l',
                style: TextStyle(
                  color: imailGreen,
                  fontSize: width * 0.05,
                  fontWeight: FontWeight.w600,
                  letterSpacing: width * 0.004,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IMailMarkPainter extends CustomPainter {
  const _IMailMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final envelope = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.17, size.height * 0.38, size.width * 0.7, size.height * 0.48),
      Radius.circular(size.width * 0.08),
    );
    canvas.drawRRect(envelope, Paint()..color = imailGreen);

    final flap = Path()
      ..moveTo(size.width * 0.18, size.height * 0.43)
      ..lineTo(size.width * 0.52, size.height * 0.67)
      ..lineTo(size.width * 0.86, size.height * 0.43);
    canvas.drawPath(
      flap,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.075
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.44, size.height * 0.22, size.width * 0.17, size.height * 0.43),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(stem, Paint()..color = imailGreen);
    canvas.drawCircle(
      Offset(size.width * 0.525, size.height * 0.12),
      size.width * 0.095,
      Paint()..color = imailGold,
    );

    final orbit = Path()
      ..moveTo(size.width * 0.12, size.height * 0.74)
      ..cubicTo(
        size.width * 0.00,
        size.height * 0.53,
        size.width * 0.03,
        size.height * 0.25,
        size.width * 0.31,
        size.height * 0.2,
      );
    canvas.drawPath(
      orbit,
      Paint()
        ..color = imailGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.035
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(size.width * 0.12, size.height * 0.74), size.width * 0.035, Paint()..color = imailGold);
    canvas.drawCircle(Offset(size.width * 0.31, size.height * 0.2), size.width * 0.035, Paint()..color = imailGold);

    final pixels = Paint()..color = imailEmerald;
    final unit = size.width * 0.055;
    for (final point in const [
      Offset(0.22, 0.39),
      Offset(0.29, 0.34),
      Offset(0.35, 0.30),
      Offset(0.23, 0.47),
      Offset(0.31, 0.45),
      Offset(0.18, 0.52),
    ]) {
      canvas.drawRect(Rect.fromLTWH(size.width * point.dx, size.height * point.dy, unit, unit), pixels);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
