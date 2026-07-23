// widgets/message_bubble.dart — пузырь сообщения в ленте чата.
// Вынесен из chat_panel.dart. Умеет: цитату ответа (reply), кликабельные
// ссылки, показ отредактированного текста с пометкой «изменено»,
// контекстное меню (Ответить / Редактировать / Переслать / Удалить у всех /
// Повторить отправку / Удалить).

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import 'common.dart';
import 'file_preview.dart';
import 'linkify_text.dart';

// ─── Общие помощники (используются и пузырём, и композером) ─────────────────

// Убирает из текста ответа служебную «цитату-заглушку» (fallback),
// которую протокол Matrix добавляет в начало body:
//   > <@user:server> старый текст
//   > вторая строка цитаты
//   (пустая строка)
//   сам ответ
String stripReplyFallback(String body) {
  if (!body.startsWith('> ')) return body;
  final lines = body.split('\n');
  var i = 0;
  while (i < lines.length && lines[i].startsWith('> ')) {
    i++;
  }
  if (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  return lines.skip(i).join('\n');
}

// Короткий текст события для плашек и цитат (файлы — со скрепкой).
String eventSnippet(matrix.Event e) {
  final isFile =
      e.messageType == matrix.MessageTypes.File ||
      e.messageType == matrix.MessageTypes.Image ||
      e.messageType == matrix.MessageTypes.Video ||
      e.messageType == matrix.MessageTypes.Audio;
  final text = stripReplyFallback(e.body);
  return isFile ? '📎 $text' : text;
}

// ─── Пузырь ─────────────────────────────────────────────────────────────────

class MessageBubble extends StatelessWidget {
  final matrix.Event event;
  final matrix.Room room;
  final matrix.Timeline timeline;
  final bool isOwn;
  final bool showAuthor;
  final String senderName;
  final VoidCallback onForward;
  final VoidCallback onReply;

  // Вызывается с ТЕКУЩИМ (уже отредактированным) текстом сообщения —
  // композер подставит его в поле ввода.
  final void Function(String currentText) onEdit;

  const MessageBubble({
    super.key,
    required this.event,
    required this.room,
    required this.timeline,
    required this.isOwn,
    required this.showAuthor,
    required this.senderName,
    required this.onForward,
    required this.onReply,
    required this.onEdit,
  });

  bool get _isFile =>
      event.messageType == matrix.MessageTypes.File ||
      event.messageType == matrix.MessageTypes.Image ||
      event.messageType == matrix.MessageTypes.Video ||
      event.messageType == matrix.MessageTypes.Audio;

  bool get _isReply => event.relationshipType == 'm.in_reply_to';

  // Событие «как показывать»: если сообщение редактировали, SDK подставит
  // последний текст (m.replace).
  matrix.Event get _display {
    try {
      return event.getDisplayEvent(timeline);
    } catch (_) {
      return event;
    }
  }

  // Было ли сообщение отредактировано (для пометки «изменено»).
  bool get _edited {
    try {
      return event.hasAggregatedEvents(timeline, 'm.replace');
    } catch (_) {
      return false;
    }
  }

  // Галочки статуса на СИНЕМ пузыре — светлые (иначе не видно).
  Widget _ownTicks(int status) {
    switch (status) {
      case -2:
        return const Icon(
          Icons.error_outline,
          size: 14,
          color: Colors.amberAccent,
        );
      case -1:
        return const Icon(Icons.schedule, size: 14, color: Colors.white54);
      case 2:
        return const Icon(Icons.done_all, size: 15, color: Colors.white);
      case 0:
      default:
        return const Icon(Icons.check, size: 15, color: Colors.white70);
    }
  }

  // Блок-цитата внутри пузыря: на что был дан этот ответ.
  Widget _quotedBlock() {
    return FutureBuilder<matrix.Event?>(
      future: event.getReplyEvent(timeline),
      builder: (context, snap) {
        final src = snap.data;
        final name = src == null
            ? '…'
            : room
                  .unsafeGetUserFromMemoryOrFallback(src.senderId)
                  .calcDisplayname();
        String text;
        if (src == null) {
          text = snap.connectionState == ConnectionState.done
              ? 'Сообщение недоступно'
              : 'Загрузка…';
        } else if (src.redacted) {
          text = 'Сообщение удалено';
        } else {
          text = eventSnippet(src);
        }
        final baseColor = isOwn ? Colors.white : T.steel;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: (isOwn ? Colors.white : T.steel).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: isOwn ? Colors.white70 : T.gold,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: baseColor,
                ),
              ),
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isOwn ? Colors.white70 : T.textSec,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = event.originServerTs;
    final timeStr =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final fwdFrom = event.content['kz.sgo.forwarded_from'] as String?;

    String bodyText = _display.body;
    final waitingKeys =
        event.type == 'm.room.encrypted' &&
        (bodyText.isEmpty || bodyText.contains('Unknown'));
    if (waitingKeys) bodyText = '⏳ Идет запрос ключей шифрования...';
    // У ответов убираем из текста служебную цитату-заглушку.
    if (_isReply && !waitingKeys) bodyText = stripReplyFallback(bodyText);

    final textColor = isOwn ? Colors.white : T.text;
    final metaColor = isOwn ? Colors.white70 : T.hint;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        onLongPressStart: (d) => _menu(context, d.globalPosition),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: isOwn ? T.ownBubble : T.inBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isOwn ? 16 : 5),
              bottomRight: Radius.circular(isOwn ? 5 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAuthor)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: T.steel,
                    ),
                  ),
                ),
              if (fwdFrom != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shortcut, size: 14, color: metaColor),
                      const SizedBox(width: 4),
                      Text(
                        'Переслано от $fwdFrom',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: metaColor,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isReply && !waitingKeys) _quotedBlock(),
              if (_isFile && !waitingKeys)
                FileAttachment(event: event)
              else
                LinkifyText(
                  text: bodyText,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.3,
                    color: textColor,
                  ),
                  linkColor: isOwn ? Colors.white : T.accent,
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_edited) ...[
                    Text(
                      'изменено',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        color: metaColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 11, color: metaColor),
                  ),
                  if (isOwn) ...[
                    const SizedBox(width: 4),
                    _ownTicks(ownEventStatus(event, room)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _menu(BuildContext context, Offset pos) async {
    // Ошибка отправки? (тот же статус, по которому рисуется янтарный значок)
    final isError = ownEventStatus(event, room) == -2;

    final List<PopupMenuEntry<String>> items = [];
    if (isOwn && isError) {
      // Для «красных» (неотправленных) — повтор и удаление из своего чата.
      items.add(
        const PopupMenuItem(value: 'retry', child: Text('Повторить отправку')),
      );
      items.add(
        const PopupMenuItem(
          value: 'delete',
          child: Text('Удалить', style: TextStyle(color: Colors.red)),
        ),
      );
    } else {
      items.add(const PopupMenuItem(value: 'reply', child: Text('Ответить')));
      // Редактировать можно только СВОЙ ТЕКСТ (не файлы).
      if (isOwn && !_isFile) {
        items.add(
          const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
        );
      }
      items.add(
        const PopupMenuItem(value: 'forward', child: Text('Переслать...')),
      );
      // Своё успешно отправленное сообщение можно удалить у всех участников.
      if (isOwn) {
        items.add(
          const PopupMenuItem(
            value: 'redact',
            child: Text('Удалить у всех', style: TextStyle(color: Colors.red)),
          ),
        );
      }
    }

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: items,
    );
    if (!context.mounted) return;

    switch (action) {
      case 'reply':
        onReply();
        break;
      case 'edit':
        // Передаём актуальный (уже отредактированный) текст без цитаты.
        onEdit(stripReplyFallback(_display.body));
        break;
      case 'forward':
        onForward();
        break;
      case 'retry':
        await event.sendAgain();
        break;
      case 'delete':
        await event.cancelSend();
        break;
      case 'redact':
        await _confirmRedact(context);
        break;
    }
  }

  // Удаление у всех участников (redaction). Действие необратимо, поэтому
  // спрашиваем подтверждение.
  Future<void> _confirmRedact(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить у всех?'),
        content: const Text(
          'Сообщение будет удалено у всех участников чата. '
          'Отменить это действие нельзя.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await event.redactEvent();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось удалить: $e')));
    }
  }
}
