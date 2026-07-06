// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import '../services/matrix_service.dart';
import 'chat_panel.dart';
import 'login_screen.dart';
import 'new_chat_search_sheet.dart';
import 'sessions_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  final MatrixService matrixService;

  const WorkspaceScreen({super.key, required this.matrixService});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final matrix.Client _client;
  matrix.Room? _selectedRoom;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _client = widget.matrixService.client!;

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _client.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  void _openNewChatSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => NewChatSearchSheet(
        client: _client,
        onChatOpened: (room) {
          Navigator.pop(context);
          setState(() {
            _selectedRoom = room;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Row(
        children: [
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
          const Expanded(
            child: Text(
              'ABYROY // CHAT',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.person_add_alt,
                  color: Color(0xFF00E676),
                  size: 18,
                ),
                tooltip: 'Найти человека или группу',
                onPressed: () => _openNewChatSearch(context),
              ),
              IconButton(
                icon: const Icon(
                  Icons.security,
                  color: Color(0xFF888888),
                  size: 18,
                ),
                tooltip: 'Мои сеансы',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SessionsScreen(
                        client: _client,
                        onLogoutCurrentDevice: () {
                          Navigator.of(context).pop();
                          _logout();
                        },
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(
                  Icons.logout,
                  color: Color(0xFF7A7A7A),
                  size: 18,
                ),
                tooltip: 'Выйти из аккаунта',
                onPressed: _logout,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Поиск по каналам...',
          hintStyle: const TextStyle(color: Color(0xFF666666)),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF666666),
            size: 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF666666),
                    size: 16,
                  ),
                  onPressed: () => _searchController.clear(),
                )
              : null,
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
        var rooms = _client.rooms;

        if (_searchQuery.isNotEmpty) {
          rooms = rooms.where((room) {
            final title = room.getLocalizedDisplayname().toLowerCase();
            return title.contains(_searchQuery);
          }).toList();
        }

        if (rooms.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isNotEmpty
                  ? 'Ничего не найдено'
                  : 'Нет активных каналов',
              style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
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

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: isSelected
                    ? const Color(0xFF1E2E25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
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
              'Выберите канал слева для начала работы',
              style: TextStyle(color: Color(0xFF333333), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
