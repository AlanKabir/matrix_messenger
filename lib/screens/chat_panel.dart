import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

class ChatPanel extends StatefulWidget {
  final matrix.Room room;

  const ChatPanel({super.key, required this.room});

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

    // Как только загрузили таймлайн — отмечаем чат прочитанным,
    // чтобы счётчик непрочитанных сообщений сбросился
    _timelineFuture.then((timeline) {
      timeline.setReadMarker();
    });
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
      _loadTimeline();
    }
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

  @override
  Widget build(BuildContext context) {
    final roomTitle = widget.room.getLocalizedDisplayname();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161616),
        elevation: 1,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF0D3823),
              child: Text(
                roomTitle.isNotEmpty ? roomTitle[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              roomTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<matrix.Timeline>(
              future: _timelineFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)),
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

                final events = snapshot.data!.events;
                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'Канал пуст. Напишите первое сообщение.',
                      style: TextStyle(color: Color(0xFF444444)),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(20),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];

                    if (event.relationshipEventId != null ||
                        (event.type != 'm.room.message' &&
                            event.type != 'm.room.encrypted')) {
                      return const SizedBox.shrink();
                    }

                    final isOwn = event.senderId == widget.room.client.userID;

                    String bodyText = event.body;

                    if (event.type == 'm.room.encrypted' &&
                        (bodyText.isEmpty || bodyText.contains('Unknown'))) {
                      bodyText = "⏳ Идет запрос ключей шифрования...";
                    }

                    return _buildBubble(
                      bodyText,
                      event.senderId,
                      isOwn,
                      event.originServerTs,
                    );
                  },
                );
              },
            ),
          ),
          _buildInputTerminal(),
        ],
      ),
    );
  }

  Widget _buildBubble(String text, String senderId, bool isOwn, DateTime ts) {
    final timeStr =
        "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isOwn ? const Color(0xFF0D3823) : const Color(0xFF1E1E1E),
          border: isOwn
              ? Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.4),
                  width: 1,
                )
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOwn ? 14 : 2),
            bottomRight: Radius.circular(isOwn ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOwn)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  senderId,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                timeStr,
                style: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputTerminal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(top: BorderSide(color: Color(0xFF262626), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _sendMessage,
              },
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText:
                      'Написать сообщение (Enter - отправить, Shift+Enter - перенос)...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0D0D0D),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: IconButton(
              padding: const EdgeInsets.all(12),
              icon: const Icon(Icons.send, color: Colors.black, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
