// screens/chat_panel.dart — окно переписки в стиле SGO (сине-золотой).
// После рефакторинга здесь только КАРКАС: шапка, лента, drag-and-drop.
// Пузырь сообщения → widgets/message_bubble.dart
// Поле ввода (+ reply/edit/Ctrl+V) → widgets/message_composer.dart
// Логика Timeline (getTimeline + onUpdate + setReadMarker) сохранена;
// плюс фильтр по cleared_ts (пустой чат после удаления).

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import 'group_info_screen.dart';

class ChatPanel extends StatefulWidget {
  final matrix.Room room;
  final MatrixService service;

  const ChatPanel({super.key, required this.room, required this.service});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late Future<matrix.Timeline> _timelineFuture;

  // Композер: через этот ключ пузыри запускают ответ/редактирование,
  // а drag-and-drop отдаёт файлы на отправку.
  final GlobalKey<MessageComposerState> _composerKey =
      GlobalKey<MessageComposerState>();

  // true, пока файл «висит» над областью чата (для подсветки).
  bool _dragging = false;

  void _loadTimeline() {
    _timelineFuture = widget.room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    _timelineFuture.then((t) => t.setReadMarker());
  }

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _composerKey.currentState?.cancelContext();
      _loadTimeline();
    }
  }

  // Обработка перетащенных файлов (может быть несколько сразу).
  Future<void> _onDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty) return;
    int sent = 0;
    for (final file in detail.files) {
      try {
        final bytes = await file.readAsBytes();
        final name = file.name;
        await _composerKey.currentState?.sendFile(bytes, name);
        sent++;
      } catch (_) {
        // Например, бросили папку или файл без прав чтения — пропускаем.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось отправить: ${file.name}')),
          );
        }
      }
    }
    if (mounted && sent > 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Отправлено файлов: $sent')));
    }
  }

  Future<void> _forward(matrix.Event event) async {
    final target = await showForwardPicker(context, widget.room.client);
    if (target != null) {
      await widget.service.forwardEvent(event, target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Переслано в «${target.getLocalizedDisplayname()}»'),
          ),
        );
      }
    }
  }

  String _senderName(matrix.Event e) {
    final user = widget.room.unsafeGetUserFromMemoryOrFallback(e.senderId);
    return user.calcDisplayname();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final title = room.getLocalizedDisplayname();
    final isGroup = !room.isDirectChat;

    return Column(
      children: [
        // ------ шапка ------
        Material(
          color: T.panelAlt,
          child: InkWell(
            onTap: isGroup
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupInfoScreen(room: room),
                    ),
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  InitialsAvatar(name: title, group: isGroup),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: T.accent,
                          ),
                        ),
                        if (isGroup)
                          Text(
                            '${room.getParticipants().length} участников',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: T.textSec,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (room.encrypted)
                    const Tooltip(
                      message: 'Сквозное шифрование включено',
                      child: Icon(Icons.lock, size: 16, color: T.accent),
                    ),
                  if (isGroup)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.chevron_right, color: T.hint, size: 20),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: T.border),
        // ------ лента (с зоной приёма перетащенных файлов) ------
        Expanded(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) {
              setState(() => _dragging = false);
              _onDrop(detail);
            },
            child: Stack(
              children: [
                Container(
                  color: T.feedBg,
                  child: FutureBuilder<matrix.Timeline>(
                    future: _timelineFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: T.accent),
                        );
                      }
                      if (!snapshot.hasData || snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'Ошибка загрузки сообщений',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        );
                      }
                      final timeline = snapshot.data!;
                      // Если чат был «удалён» — показываем только сообщения ПОЗЖЕ
                      // метки удаления (старая история скрыта у меня).
                      final clearedTs = widget.service.clearedTsFor(room.id);
                      final events = timeline.events
                          .where(
                            (e) =>
                                // Обычные сообщения (без связи) и ОТВЕТЫ
                                // показываем; правки/реакции — нет
                                // (правки подставляются в исходный пузырь).
                                (e.relationshipEventId == null ||
                                    e.relationshipType == 'm.in_reply_to') &&
                                // удалённые «у всех» не показываем вовсе
                                !e.redacted &&
                                (e.type == 'm.room.message' ||
                                    e.type == 'm.room.encrypted') &&
                                (clearedTs == null ||
                                    e.originServerTs.millisecondsSinceEpoch >
                                        clearedTs),
                          )
                          .toList();
                      if (events.isEmpty) {
                        return const Center(
                          child: Text(
                            'Нет сообщений. Напишите первое.',
                            style: TextStyle(color: T.hint),
                          ),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 40,
                        ),
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final isOwn =
                              event.senderId == widget.room.client.userID;
                          return MessageBubble(
                            event: event,
                            room: room,
                            timeline: timeline,
                            isOwn: isOwn,
                            showAuthor: isGroup && !isOwn,
                            senderName: _senderName(event),
                            onForward: () => _forward(event),
                            onReply: () =>
                                _composerKey.currentState?.startReply(event),
                            onEdit: (currentText) => _composerKey.currentState
                                ?.startEdit(event, currentText),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Подсветка-подсказка, когда над чатом «висит» файл.
                if (_dragging)
                  Positioned.fill(
                    child: Container(
                      color: T.accent.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: T.panelAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: T.accent, width: 2),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.file_download_outlined,
                              size: 40,
                              color: T.accent,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Отпустите файл, чтобы отправить',
                              style: TextStyle(
                                color: T.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ------ композер (плашки ответа/редактирования внутри) ------
        MessageComposer(key: _composerKey, room: room),
      ],
    );
  }
}
