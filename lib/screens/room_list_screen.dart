import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import '../services/matrix_service.dart';
import 'chat_screen.dart'; // Подключили боевой чат!

class RoomListScreen extends StatefulWidget {
  final MatrixService matrixService;

  const RoomListScreen({super.key, required this.matrixService});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  late final matrix.Client _client;

  @override
  void initState() {
    super.initState();
    _client = widget.matrixService.client!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'MATRIX // Каналы связи',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20),
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF00E676),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Поиск по защищенным комнатам...',
                hintStyle: const TextStyle(color: Color(0xFF666666)),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF666666),
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: _client.onSync.stream,
              builder: (context, snapshot) {
                final rooms = _client.rooms;

                if (rooms.isEmpty) {
                  return const Center(
                    child: Text(
                      'Нет активных шифрованных каналов',
                      style: TextStyle(
                        color: Color(0xFF666666),
                        letterSpacing: 1,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rooms.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Color(0xFF1F1F1F), height: 1),
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final unread = room.notificationCount;

                    final rawTitle = room.getLocalizedDisplayname();
                    final title = rawTitle.isNotEmpty
                        ? rawTitle
                        : 'Пустая комната';
                    final firstLetter = title[0].toUpperCase();

                    final lastMsg = room.lastEvent?.body;
                    final subtitle = (lastMsg != null && lastMsg.isNotEmpty)
                        ? lastMsg
                        : 'Нет сообщений';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFF162B21),
                        child: Text(
                          firstLetter,
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
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
                          fontSize: 15,
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
                            fontSize: 13,
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
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF333333),
                              size: 18,
                            ),

                      onTap: () {
                        // ТЕЛЕПОРТ В ЧАТ: Плавный слайд справа налево
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (context, a1, a2) =>
                                ChatScreen(room: room),
                            transitionsBuilder: (context, a1, a2, child) =>
                                SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(a1),
                                  child: child,
                                ),
                            transitionDuration: const Duration(
                              milliseconds: 300,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
