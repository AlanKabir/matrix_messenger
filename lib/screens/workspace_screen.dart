// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import '../services/matrix_service.dart';

class WorkspaceScreen extends StatefulWidget {
  final MatrixService matrixService;

  const WorkspaceScreen({super.key, required this.matrixService});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final matrix.Client _client;
  matrix.Room? _selectedRoom;

  @override
  void initState() {
    super.initState();
    _client = widget.matrixService.client!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Row(
        children: [
          // ================= ЛЕВАЯ ПАНЕЛЬ =================
          Container(
            width: 340,
            decoration: const BoxDecoration(
              color: Color(0xFF161616),
              border: Border(
                right: BorderSide(color: Color(0xFF262626), width: 1),
              ),
            ),
            child: Column(
              children: [
                _buildSidebarHeader(),
                _buildSearchBar(),
                Expanded(child: _buildRoomList()),
              ],
            ),
          ),

          // ================= ПРАВАЯ ПАНЕЛЬ =================
          Expanded(
            child: _selectedRoom == null
                ? _buildEmptyPlaceholder()
                : ChatPanel(room: _selectedRoom!),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'MATRIX // КОМАНДНЫЙ ЦЕНТР',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF00E676),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Поиск по шифрованным каналам...',
          hintStyle: const TextStyle(color: Color(0xFF666666)),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF666666),
            size: 18,
          ),
          filled: true,
          fillColor: const Color(0xFF1F1F1F),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildRoomList() {
    return StreamBuilder(
      stream: _client.onSync.stream,
      builder: (context, snapshot) {
        final rooms = _client.rooms;

        if (rooms.isEmpty) {
          return const Center(
            child: Text(
              'Нет активных каналов',
              style: TextStyle(color: Color(0xFF666666), fontSize: 13),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: rooms.length,
          separatorBuilder: (context, index) =>
              const Divider(color: Color(0xFF1F1F1F), height: 1),
          itemBuilder: (context, index) {
            final room = rooms[index];
            final unread = room.notificationCount;
            final isSelected = _selectedRoom?.id == room.id;

            final rawTitle = room.getLocalizedDisplayname();
            final title = rawTitle.isNotEmpty ? rawTitle : 'Пустая комната';
            final firstLetter = title[0].toUpperCase();

            final lastMsg = room.lastEvent?.body;
            final subtitle = (lastMsg != null && lastMsg.isNotEmpty)
                ? lastMsg
                : 'Нет сообщений';

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1E2E25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: isSelected
                      ? const Color(0xFF00E676)
                      : const Color(0xFF222222),
                  child: Text(
                    firstLetter,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : const Color(0xFF00E676),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
                    ),
                  ),
                ),
                trailing: unread > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF00E676),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unread.toString(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  setState(() {
                    _selectedRoom = room;
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyPlaceholder() {
    return Container(
      color: const Color(0xFF121212),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 72, color: Color(0xFF222222)),
            SizedBox(height: 16),
            Text(
              'Терминал в режиме ожидания',
              style: TextStyle(
                color: Color(0xFF555555),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Выберите защищенный канал слева для дешифровки',
              style: TextStyle(color: Color(0xFF333333), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// ================= ВНУТРЕННИЙ МОДУЛЬ ПРАВОГО ЭКРАНА ==================
// =====================================================================

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
    if (text.isEmpty) {
      // <-- ИСПРАВЛЕНО №1: заперто в скобки
      return;
    }
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
                      'Ошибка дешифровки стека',
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
                        event.type != 'm.room.message') {
                      // <-- ИСПРАВЛЕНО №2: заперто в скобки
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
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Написать в защищенный чат...',
                hintStyle: const TextStyle(color: Color(0xFF555555)),
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
