// widgets/linkify_text.dart — текст сообщения с кликабельными ссылками.
// Находит в тексте http://, https:// и www.-адреса и делает их ссылками,
// открывающимися в системном браузере. Всё остальное — обычный текст.
//
// Использование (вместо обычного Text в пузыре):
//   LinkifyText(text: bodyText, style: TextStyle(...), linkColor: ...)

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkifyText extends StatefulWidget {
  final String text;
  final TextStyle style;

  // Цвет ссылки. Если не задан — берётся из style с подчёркиванием.
  final Color? linkColor;

  const LinkifyText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor,
  });

  @override
  State<LinkifyText> createState() => _LinkifyTextState();
}

class _LinkifyTextState extends State<LinkifyText> {
  // Распознаём: http://..., https://..., www....
  // Хвостовые знаки препинания (точка, запятая, скобка) в ссылку не входят.
  static final RegExp _urlRe = RegExp(
    r'(https?:\/\/[^\s<>]+|www\.[^\s<>]+)',
    caseSensitive: false,
  );

  // Распознаватели кликов нужно создавать один раз и обязательно
  // освобождать в dispose — иначе утечка памяти на каждый пузырь.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(covariant LinkifyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  Future<void> _open(String raw) async {
    // Отрезаем случайно прилипшие знаки препинания в конце.
    var url = raw.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
    if (url.toLowerCase().startsWith('www.')) {
      url = 'http://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть ссылку: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final linkStyle = widget.style.copyWith(
      color: widget.linkColor ?? widget.style.color,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor ?? widget.style.color,
    );

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _urlRe.allMatches(widget.text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final url = m.group(0)!;
      final rec = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(rec);
      spans.add(TextSpan(text: url, style: linkStyle, recognizer: rec));
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }

    // Ссылок нет — обычный текст без лишней обвязки.
    if (_recognizers.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    return SelectionContainer.disabled(
      child: Text.rich(TextSpan(style: widget.style, children: spans)),
    );
  }
}
