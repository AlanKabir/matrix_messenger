// screens/chat_panel.dart — окно переписки в стиле SGO (сине-золотой).
// Логика Timeline (getTimeline + onUpdate + setReadMarker) сохранена;
// плюс фильтр по cleared_ts (пустой чат после удаления), файлы, пересылка.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import '../widgets/file_preview.dart';

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
    if (oldWidget.room.id != widget.room.id) _loadTimeline();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    widget.room.sendTextEvent(text);
    _messageController.clear();
  }

  Future<void> _attachFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    await widget.room.sendFileEvent(
      matrix.MatrixFile(bytes: f.bytes!, name: f.name),
    );
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
        Container(
          color: T.panelAlt,
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
                    Text(
                      isGroup
                          ? '${room.getParticipants().length} участников'
                          : room.directChatMatrixID ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: T.textSec),
                    ),
                  ],
                ),
              ),
              if (room.encrypted)
                const Tooltip(
                  message: 'Сквозное шифрование включено',
                  child: Icon(Icons.lock, size: 16, color: T.accent),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: T.border),
        // ------ лента ------
        Expanded(
          child: Container(
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
                // Если чат был «удалён» — показываем только сообщения ПОЗЖЕ
                // метки удаления (старая история скрыта у меня).
                final clearedTs = widget.service.clearedTsFor(room.id);
                final events = snapshot.data!.events
                    .where(
                      (e) =>
                          e.relationshipEventId == null &&
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
                    final isOwn = event.senderId == widget.room.client.userID;
                    return _Bubble(
                      event: event,
                      room: room,
                      isOwn: isOwn,
                      showAuthor: isGroup && !isOwn,
                      senderName: _senderName(event),
                      onForward: () => _forward(event),
                    );
                  },
                );
              },
            ),
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
                  },
                  child: TextField(
                    controller: _messageController,
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
  final bool isOwn;
  final bool showAuthor;
  final String senderName;
  final VoidCallback onForward;

  const _Bubble({
    required this.event,
    required this.room,
    required this.isOwn,
    required this.showAuthor,
    required this.senderName,
    required this.onForward,
  });

  bool get _isFile =>
      event.messageType == matrix.MessageTypes.File ||
      event.messageType == matrix.MessageTypes.Image ||
      event.messageType == matrix.MessageTypes.Video ||
      event.messageType == matrix.MessageTypes.Audio;

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

    final textColor = isOwn ? Colors.white : T.text;
    final metaColor = isOwn ? Colors.white70 : T.hint;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        onLongPress: onForward,
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
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'forward', child: Text('Переслать...')),
      ],
    );
    if (action == 'forward') onForward();
  }
}
