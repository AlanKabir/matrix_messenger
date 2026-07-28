// widgets/message_bubble.dart — пузырь сообщения в ленте чата.
// Умеет: цитату ответа (reply) с переходом к оригиналу по клику,
// кликабельные ссылки, показ отредактированного текста с пометкой
// «изменено», подсветку при прыжке к сообщению, контекстное меню
// (Ответить / Редактировать / Закрепить / Переслать / Удалить у всех /
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

  // Прыжок к сообщению по id (клик по цитате ответа).
  final void Function(String eventId)? onJumpTo;

  // Подсветить пузырь (после прыжка к нему).
  final bool highlighted;

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
    this.onJumpTo,
    this.highlighted = false,
  });

  bool get _isFile =>
      event.messageType == matrix.MessageTypes.File ||
      event.messageType == matrix.MessageTypes.Image ||
      event.messageType == matrix.MessageTypes.Video ||
      event.messageType == matrix.MessageTypes.Audio;

  // ID сообщения, на которое отвечали. В matrix 7.4.0 нет готового
  // распознавания m.in_reply_to, поэтому читаем содержимое события сами —
  // так работает в любой версии SDK.
  String? get _replyToId {
    final rel = event.content['m.relates_to'];
    if (rel is Map) {
      final inReply = rel['m.in_reply_to'];
      if (inReply is Map) {
        final id = inReply['event_id'];
        if (id is String && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  bool get _isReply => _replyToId != null;

  // Ищем цитируемое сообщение сначала в загруженной ленте, потом на сервере.
  Future<matrix.Event?> _fetchQuoted() async {
    final id = _replyToId;
    if (id == null) return null;
    try {
      for (final e in timeline.events) {
        if (e.eventId == id) return e;
      }
    } catch (_) {}
    try {
      return await room.getEventById(id);
    } catch (_) {
      return null;
    }
  }

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
  // Клик по цитате — прыжок к оригинальному сообщению.
  Widget _quotedBlock() {
    return GestureDetector(
      onTap: () {
        final id = _replyToId;
        if (id != null) onJumpTo?.call(id);
      },
      child: FutureBuilder<matrix.Event?>(
        future: _fetchQuoted(),
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
      ),
    );
  }

  // ─── Реакции (m.reaction) ──────────────────────────────────────────────

  // Карта «эмодзи → список событий-реакций».
  Map<String, List<matrix.Event>> _reactions() {
    final map = <String, List<matrix.Event>>{};
    try {
      final aggregated = event.aggregatedEvents(timeline, 'm.annotation');
      for (final e in aggregated) {
        if (e.redacted) continue;
        final rel = e.content['m.relates_to'];
        if (rel is Map) {
          final key = rel['key'];
          if (key is String && key.isNotEmpty) {
            map.putIfAbsent(key, () => []).add(e);
          }
        }
      }
    } catch (_) {}
    return map;
  }

  // Поставить/снять свою реакцию.
  Future<void> _toggleReaction(BuildContext context, String emoji) async {
    final me = room.client.userID;
    final mine = _reactions()[emoji]?.where((e) => e.senderId == me).toList();
    try {
      if (mine != null && mine.isNotEmpty) {
        await mine.first.redactEvent();
      } else {
        await room.sendReaction(event.eventId, emoji);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось поставить реакцию: $e')),
      );
    }
  }

  // Кто поставил реакции — список по эмодзи.
  void _showWhoReacted(BuildContext context) {
    final map = _reactions();
    if (map.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Реакции'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in map.entries)
                for (final r in entry.value)
                  ListTile(
                    dense: true,
                    leading: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 20),
                    ),
                    title: Text(
                      room
                          .unsafeGetUserFromMemoryOrFallback(r.senderId)
                          .calcDisplayname(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // Полоска реакций под текстом сообщения.
  Widget _reactionsBar(BuildContext context) {
    final map = _reactions();
    if (map.isEmpty) return const SizedBox.shrink();
    final me = room.client.userID;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: map.entries.map((e) {
          final mineReacted = e.value.any((r) => r.senderId == me);
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _toggleReaction(context, e.key),
            onLongPress: () => _showWhoReacted(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isOwn
                    ? Colors.white.withValues(alpha: mineReacted ? 0.30 : 0.16)
                    : (mineReacted ? T.selected : const Color(0xFFEFF3F8)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: mineReacted
                      ? (isOwn ? Colors.white70 : T.accent)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                e.value.length > 1 ? '${e.key} ${e.value.length}' : e.key,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isOwn ? Colors.white : T.text,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Выбор эмодзи для реакции.
  Future<void> _pickReaction(BuildContext context) async {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '✅', '🔥'];
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Реакция'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: emojis
              .map(
                (e) => InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(ctx, e),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    await _toggleReaction(context, chosen);
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
    // Служебная цитата-заглушка («> <@user:server> текст») в начале тела —
    // срезаем всегда, а не только у распознанных ответов.
    if (!waitingKeys) bodyText = stripReplyFallback(bodyText);

    final textColor = isOwn ? Colors.white : T.text;
    final metaColor = isOwn ? Colors.white70 : T.hint;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        onLongPressStart: (d) => _menu(context, d.globalPosition),
        // Подсветка при прыжке: мягкая золотая «капсула» вокруг пузыря.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: highlighted
                ? T.gold.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
          ),
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
              // Белые входящие отделяем от фона рамкой; лёгкая тень
              // приподнимает все пузыри над лентой.
              border: isOwn ? null : Border.all(color: T.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
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
                _reactionsBar(context),
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
      ),
    );
  }

  void _menu(BuildContext context, Offset pos) async {
    // Ошибка отправки? (тот же статус, по которому рисуется янтарный значок)
    final isError = ownEventStatus(event, room) == -2;
    final isPinned = room.pinnedEventIds.contains(event.eventId);

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
      items.add(const PopupMenuItem(value: 'react', child: Text('Реакция…')));
      items.add(const PopupMenuItem(value: 'reply', child: Text('Ответить')));
      // Редактировать можно только СВОЙ ТЕКСТ (не файлы).
      if (isOwn && !_isFile) {
        items.add(
          const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
        );
      }
      items.add(
        PopupMenuItem(
          value: 'pin',
          child: Text(isPinned ? 'Открепить' : 'Закрепить'),
        ),
      );
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
      case 'react':
        await _pickReaction(context);
        break;
      case 'reply':
        onReply();
        break;
      case 'edit':
        // Передаём актуальный (уже отредактированный) текст без цитаты.
        onEdit(stripReplyFallback(_display.body));
        break;
      case 'pin':
        await _togglePin(context, isPinned);
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

  // Закрепить/открепить сообщение (state-событие m.room.pinned_events).
  Future<void> _togglePin(BuildContext context, bool isPinned) async {
    try {
      final ids = List<String>.from(room.pinnedEventIds);
      if (isPinned) {
        ids.remove(event.eventId);
      } else {
        ids.add(event.eventId);
      }
      await room.setPinnedEvents(ids);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось изменить закреплённые (нет прав в этой группе)',
          ),
        ),
      );
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
