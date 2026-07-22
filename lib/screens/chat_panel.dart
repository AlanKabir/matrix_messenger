// screens/chat_panel.dart — окно переписки в стиле SGO (сине-золотой).
// Логика Timeline (getTimeline + onUpdate + setReadMarker) сохранена;
// плюс фильтр по cleared_ts (пустой чат после удаления), файлы, пересылка.
// Добавлено: перетаскивание файлов (drag-and-drop) прямо в область чата.
// Добавлено: ОТВЕТ на сообщение (reply, m.in_reply_to) — пункт меню
// «Ответить», плашка цитаты над полем ввода, цитата внутри пузыря.

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import '../widgets/file_preview.dart';
import 'group_info_screen.dart';

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

class ChatPanel extends StatefulWidget {
  final matrix.Room room;
  final MatrixService service;

  const ChatPanel({super.key, required this.room, required this.service});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late Future<matrix.Timeline> _timelineFuture;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  // true, пока файл «висит» над областью чата (для подсветки).
  bool _dragging = false;

  // Сообщение, на которое сейчас отвечаем (null — обычная отправка).
  matrix.Event? _replyTo;

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
      _replyTo = null; // цитата из другого чата тут не нужна
      _loadTimeline();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    widget.room.sendTextEvent(text, inReplyTo: _replyTo);
    _messageController.clear();
    if (_replyTo != null) setState(() => _replyTo = null);
  }

  // Начать ответ на сообщение: показать плашку и поставить курсор в поле.
  void _startReply(matrix.Event event) {
    setState(() => _replyTo = event);
    _inputFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  // Единая отправка файла — используется и кнопкой, и перетаскиванием.
  Future<void> _sendFileBytes(Uint8List bytes, String name) async {
    await widget.room.sendFileEvent(
      matrix.MatrixFile(bytes: bytes, name: name),
      inReplyTo: _replyTo,
    );
    if (_replyTo != null && mounted) setState(() => _replyTo = null);
  }

  // Кнопка «прикрепить файл».
  Future<void> _attachFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    await _sendFileBytes(f.bytes!, f.name);
  }

  // Обработка перетащенных файлов (может быть несколько сразу).
  Future<void> _onDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty) return;
    int sent = 0;
    for (final file in detail.files) {
      try {
        final bytes = await file.readAsBytes();
        final name = file.name;
        await _sendFileBytes(bytes, name);
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

  // Короткий текст для плашки цитаты (файл — со скрепкой).
  String _replySnippet(matrix.Event e) {
    final isFile =
        e.messageType == matrix.MessageTypes.File ||
        e.messageType == matrix.MessageTypes.Image ||
        e.messageType == matrix.MessageTypes.Video ||
        e.messageType == matrix.MessageTypes.Audio;
    final text = stripReplyFallback(e.body);
    return isFile ? '📎 $text' : text;
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
                                // показываем; правки/реакции — нет.
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
                          return _Bubble(
                            event: event,
                            room: room,
                            timeline: timeline,
                            isOwn: isOwn,
                            showAuthor: isGroup && !isOwn,
                            senderName: _senderName(event),
                            onForward: () => _forward(event),
                            onReply: () => _startReply(event),
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
        // ------ плашка «Ответ на …» над полем ввода ------
        if (_replyTo != null)
          Container(
            color: T.panelAlt,
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.reply, size: 18, color: T.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: T.gold, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _senderName(_replyTo!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: T.steel,
                          ),
                        ),
                        Text(
                          _replySnippet(_replyTo!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: T.textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Отменить ответ',
                  icon: const Icon(Icons.close, size: 18, color: T.hint),
                  onPressed: _cancelReply,
                ),
              ],
            ),
          ),
        // ------ композер ------
        Container(
          color: T.panelAlt,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Прикрепить файл',
                icon: const Icon(Icons.attach_file, color: T.hint),
                onPressed: _attachFile,
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter):
                        _sendMessage,
                    // Esc — отменить ответ.
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _cancelReply,
                  },
                  child: TextField(
                    controller: _messageController,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Сообщение…',
                      hintStyle: const TextStyle(color: T.hint),
                      filled: true,
                      fillColor: const Color(0xFFF2F5F9),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: T.gold),
                icon: const Icon(
                  Icons.arrow_upward,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
class _Bubble extends StatelessWidget {
  final matrix.Event event;
  final matrix.Room room;
  final matrix.Timeline timeline;
  final bool isOwn;
  final bool showAuthor;
  final String senderName;
  final VoidCallback onForward;
  final VoidCallback onReply;

  const _Bubble({
    required this.event,
    required this.room,
    required this.timeline,
    required this.isOwn,
    required this.showAuthor,
    required this.senderName,
    required this.onForward,
    required this.onReply,
  });

  bool get _isFile =>
      event.messageType == matrix.MessageTypes.File ||
      event.messageType == matrix.MessageTypes.Image ||
      event.messageType == matrix.MessageTypes.Video ||
      event.messageType == matrix.MessageTypes.Audio;

  bool get _isReply => event.relationshipType == 'm.in_reply_to';

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
          final isFile =
              src.messageType == matrix.MessageTypes.File ||
              src.messageType == matrix.MessageTypes.Image ||
              src.messageType == matrix.MessageTypes.Video ||
              src.messageType == matrix.MessageTypes.Audio;
          text = stripReplyFallback(src.body);
          if (isFile) text = '📎 $text';
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

    String bodyText = event.body;
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
                Text(
                  bodyText,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.3,
                    color: textColor,
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
