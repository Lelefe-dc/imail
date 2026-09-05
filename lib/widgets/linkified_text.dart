import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Selectable email text that turns web addresses into tappable links.
///
/// Links are opened outside iMail so the mail reader never executes remote web
/// content inside the message view.
class LinkifiedSelectableText extends StatefulWidget {
  const LinkifiedSelectableText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;

  @override
  State<LinkifiedSelectableText> createState() => _LinkifiedSelectableTextState();
}

class _LinkifiedSelectableTextState extends State<LinkifiedSelectableText> {
  static final RegExp _urlPattern = RegExp(
    r"(?:(?:https?://)|(?:www\.))[\w\-._~:/?#\[\]@!$&'()*+,;=%]+",
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  List<_TextPart> _parts = const <_TextPart>[];

  @override
  void initState() {
    super.initState();
    _rebuildParts();
  }

  @override
  void didUpdateWidget(covariant LinkifiedSelectableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _rebuildParts();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _rebuildParts() {
    _disposeRecognizers();
    final source = widget.text;
    if (source.isEmpty) {
      _parts = const <_TextPart>[];
      return;
    }

    final parts = <_TextPart>[];
    var cursor = 0;
    for (final match in _urlPattern.allMatches(source)) {
      if (match.start > cursor) {
        parts.add(_TextPart(source.substring(cursor, match.start)));
      }

      final raw = match.group(0)!;
      final cleaned = _trimTrailingPunctuation(raw);
      final suffix = raw.substring(cleaned.length);
      if (cleaned.isEmpty) {
        parts.add(_TextPart(raw));
      } else {
        final uriText = cleaned.toLowerCase().startsWith('www.')
            ? 'https://$cleaned'
            : cleaned;
        final uri = Uri.tryParse(uriText);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          parts.add(_TextPart(cleaned));
        } else {
          final recognizer = TapGestureRecognizer()..onTap = () => _open(uri);
          _recognizers.add(recognizer);
          parts.add(_TextPart(cleaned, recognizer: recognizer));
        }
        if (suffix.isNotEmpty) {
          parts.add(_TextPart(suffix));
        }
      }
      cursor = match.end;
    }

    if (cursor < source.length) {
      parts.add(_TextPart(source.substring(cursor)));
    }
    _parts = parts;
  }

  String _trimTrailingPunctuation(String value) {
    var end = value.length;
    while (end > 0 && '.,;:!?'.contains(value[end - 1])) {
      end--;
    }

    // A closing parenthesis is commonly sentence punctuation after a URL. Keep
    // balanced parentheses that are genuinely part of the URL.
    while (end > 0 && value[end - 1] == ')') {
      final candidate = value.substring(0, end);
      final opens = RegExp(r'\(').allMatches(candidate).length;
      final closes = RegExp(r'\)').allMatches(candidate).length;
      if (closes <= opens) break;
      end--;
    }
    return value.substring(0, end);
  }

  Future<void> _open(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _showOpenError();
      }
    } catch (_) {
      _showOpenError();
    }
  }

  void _showOpenError() {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Could not open this link.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLinkStyle = widget.linkStyle ??
        const TextStyle(
          color: Color(0xFF0B57D0),
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF0B57D0),
        );

    return SelectableText.rich(
      TextSpan(
        style: widget.style,
        children: _parts
            .map(
              (part) => TextSpan(
                text: part.text,
                recognizer: part.recognizer,
                style: part.recognizer == null ? null : effectiveLinkStyle,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _TextPart {
  const _TextPart(this.text, {this.recognizer});

  final String text;
  final TapGestureRecognizer? recognizer;
}
