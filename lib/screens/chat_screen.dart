// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

class ChatScreen extends StatefulWidget {
  final matrix.Room room;

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final Future<matrix.Timeline> _timelineFuture;
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Магия Matrix: привязываем реактивный слушатель событий к нашему экрану
    _timelineFuture = widget.room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    widget.room.sendTextEvent(text); // Отправка зашифрованного пакета в сеть
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final roomTitle = widget.room.getLocalizedDisplayname();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF162B21),
              child: Text(
                roomTitle.isNotEmpty ? roomTitle[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                roomTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Область сообщений
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
                      'Ошибка дешифровки стека сообщений',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  );
                }

                final events = snapshot.data!.events;

                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'Канал стерилен. Отправьте первое сообщение.',
                      style: TextStyle(color: Color(0xFF555555)),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true, // В мессенджерах новые сообщения всегда снизу
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];

                    // Отсекаем служебный системный мусор (входы/выходы юзеров)
                    if (event.relationshipEventId != null ||
                        event.type != 'm.room.message') {
                      return const SizedBox.shrink();
                    }

                    final isOwn = event.senderId == widget.room.client.userID;
                    return _buildBubble(
                      event.body,
                      event.senderId,
                      isOwn,
                      event.originServerTs,
                    );
                  },
                );
              },
            ),
          ),

          // Терминал ввода данных
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
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOwn
              ? const Color(0xFF0D3823)
              : const Color(0xFF1E1E1E), // Тёмный изумруд против графита
          border: isOwn
              ? Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.4),
                  width: 1,
                )
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOwn ? 16 : 4),
            bottomRight: Radius.circular(isOwn ? 4 : 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(top: BorderSide(color: Color(0xFF262626), width: 1)),
      ),
      child: SafeArea(
        // Защита от перекрытия системной полоской телефона
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                minLines: 1,
                maxLines: 4, // Поле плавно растет вверх при длинном тексте
                decoration: InputDecoration(
                  hintText: 'Введите сообщение...',
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  filled: true,
                  fillColor: const Color(0xFF0F0F0F),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF00E676),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.black, size: 18),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
