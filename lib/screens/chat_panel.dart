// screens/chat_panel.dart — окно переписки. Логика Timeline
// (getTimeline + onUpdate + setReadMarker) сохранена; поверх нее:
// стиль WhatsApp, галочки, отправка файлов, inline-предпросмотр, пересылка.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

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
    // Открыли чат → отмечаем прочитанным (read receipt уходит собеседнику,
    // у него сообщения становятся «2 синие»).
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
          color: const Color(0xFFF0F2F5),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      isGroup
                          ? '${room.getParticipants().length} участников'
                          : room.directChatMatrixID ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (room.encrypted)
                const Tooltip(
                  message: 'Сквозное шифрование включено',
                  child: Icon(Icons.lock, size: 16, color: kAccent),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ------ лента ------
        Expanded(
          child: Container(
            color: const Color(0xFFEFEAE2),
            child: FutureBuilder<matrix.Timeline>(
              future: _timelineFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: kAccent),
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
                // метки удаления. Старая история скрыта у меня (у собеседника
                // остаётся), поэтому вернувшийся чат открывается пустым.
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
                      style: TextStyle(color: Colors.black38),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
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
          color: const Color(0xFFF0F2F5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Прикрепить файл',
                icon: const Icon(Icons.attach_file, color: Color(0xFF54656F)),
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
                      hintText:
                          'Введите сообщение (Enter — отправить, Shift+Enter — перенос)',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: kAccent),
                icon: const Icon(Icons.send, color: Colors.white, size: 18),
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

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        onLongPress: onForward,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: isOwn ? const Color(0xFFD9FDD3) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(isOwn ? 10 : 2),
              bottomRight: Radius.circular(isOwn ? 2 : 10),
            ),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1)],
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
                      color: kAccent,
                    ),
                  ),
                ),
              if (fwdFrom != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shortcut,
                        size: 14,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Переслано от $fwdFrom',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.black45,
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
                  style: const TextStyle(fontSize: 14.5, height: 1.3),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  if (isOwn) ...[
                    const SizedBox(width: 4),
                    StatusTicks(status: ownEventStatus(event, room)),
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
