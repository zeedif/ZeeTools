import 'package:flutter/material.dart';

import 'regex_highlight_controller.dart';

class RegexTextField extends StatefulWidget {
  const RegexTextField({
    super.key,
    required this.label,
    required this.isRegexMode,
    required this.onChanged,
    this.initialValue = '',
    this.hintText,
    this.errorText,
    this.suffixIcons = const [],
  });

  final String label;
  final bool isRegexMode;
  final ValueChanged<String> onChanged;
  final String initialValue;
  final String? hintText;
  final String? errorText;
  final List<Widget> suffixIcons;

  @override
  State<RegexTextField> createState() => _RegexTextFieldState();
}

class _RegexTextFieldState extends State<RegexTextField> {
  late final RegexHighlightController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RegexHighlightController()
      ..text = widget.initialValue
      ..isRegexMode = widget.isRegexMode;
  }

  @override
  void didUpdateWidget(RegexTextField old) {
    super.didUpdateWidget(old);
    if (old.isRegexMode != widget.isRegexMode) {
      _controller.isRegexMode = widget.isRegexMode;
    }
    if (old.initialValue != widget.initialValue && widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRegex = widget.isRegexMode;

    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      minLines: 1,
      maxLines: 6,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        hintMaxLines: 1,
        errorText: widget.errorText,
        isDense: true,
        filled: true,
        fillColor: isRegex ? cs.primaryContainer.withAlpha(40) : cs.surfaceContainerHighest,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isRegex ? cs.primary.withAlpha(160) : cs.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isRegex ? cs.primary : cs.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        suffixIcon: widget.suffixIcons.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.suffixIcons,
                ),
              ),
      ),
    );
  }
}
