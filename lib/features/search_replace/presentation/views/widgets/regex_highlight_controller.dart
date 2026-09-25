import 'package:flutter/material.dart';

enum _TokenType { escape, charClass, group, quantifier, anchor, alternation, dot, literal }

class RegexHighlightController extends TextEditingController {
  bool _isRegexMode = false;

  set isRegexMode(bool value) {
    if (_isRegexMode == value) return;
    _isRegexMode = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_isRegexMode || text.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final tokens = _tokenise(text);
    final cs = Theme.of(context).colorScheme;

    Color colorFor(_TokenType t) => switch (t) {
      _TokenType.escape => const Color(0xFF00BCD4),
      _TokenType.charClass => const Color(0xFF42A5F5),
      _TokenType.group => const Color(0xFFCE93D8),
      _TokenType.quantifier => const Color(0xFFFFA726),
      _TokenType.anchor => const Color(0xFF66BB6A),
      _TokenType.alternation => const Color(0xFFFFEE58),
      _TokenType.dot => const Color(0xFFF48FB1),
      _TokenType.literal => cs.onSurface,
    };

    return TextSpan(
      style: style,
      children: tokens
          .map(
            (t) => TextSpan(
              text: t.$1,
              style: style?.copyWith(color: colorFor(t.$2)) ?? TextStyle(color: colorFor(t.$2)),
            ),
          )
          .toList(),
    );
  }

  List<(String, _TokenType)> _tokenise(String src) {
    final tokens = <(String, _TokenType)>[];
    var i = 0;

    while (i < src.length) {
      if (src[i] == r'\' && i + 1 < src.length) {
        tokens.add((src.substring(i, i + 2), _TokenType.escape));
        i += 2;
        continue;
      }

      if (src[i] == '[') {
        final end = _charClassEnd(src, i);
        tokens.add((src.substring(i, end), _TokenType.charClass));
        i = end;
        continue;
      }

      if (src[i] == '(' || src[i] == ')') {
        tokens.add((src[i], _TokenType.group));
        i++;
        continue;
      }

      if ('?*+'.contains(src[i])) {
        tokens.add((src[i], _TokenType.quantifier));
        i++;
        continue;
      }

      if (src[i] == '{') {
        final end = src.indexOf('}', i);
        if (end >= 0) {
          tokens.add((src.substring(i, end + 1), _TokenType.quantifier));
          i = end + 1;
          continue;
        }
      }

      if (src[i] == '^' || src[i] == r'$') {
        tokens.add((src[i], _TokenType.anchor));
        i++;
        continue;
      }

      if (src[i] == '|') {
        tokens.add((src[i], _TokenType.alternation));
        i++;
        continue;
      }

      if (src[i] == '.') {
        tokens.add((src[i], _TokenType.dot));
        i++;
        continue;
      }

      final start = i;
      while (i < src.length && !r'\[(){}?*+^$|.'.contains(src[i])) {
        i++;
      }
      if (i > start) {
        tokens.add((src.substring(start, i), _TokenType.literal));
      }
    }

    return tokens;
  }

  int _charClassEnd(String src, int openPos) {
    var i = openPos + 1;
    if (i < src.length && src[i] == '^') i++;
    if (i < src.length && src[i] == ']') i++;
    while (i < src.length) {
      if (src[i] == r'\') {
        i += 2;
        continue;
      }
      if (src[i] == ']') return i + 1;
      i++;
    }
    return src.length;
  }
}
