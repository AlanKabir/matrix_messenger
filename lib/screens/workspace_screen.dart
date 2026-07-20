// screens/workspace_screen.dart — ваш двухпанельный workspace,
// перестилизованный под WhatsApp (по ТЗ) + создание группы.
// Логика (onSync.stream, выбор комнаты, поиск, сеансы, logout) — ваша.

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../services/matrix_service.dart';
import '../widgets/common.dart';
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
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    // Через сервис: он гасит подписку на приглашения, потом logout.
    await widget.matrixService.logout();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _openNewChatSearch() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => NewChatSearchSheet(
        // Передаём сервис, а не голый client, чтобы личный чат
        // создавался через дедуп/автоприём.
        service: widget.matrixService,
        onChatOpened: (room) {
          Navigator.pop(context);
          setState(() => _selectedRoom = room);
        },
      ),
    );
  }

  Future<void> _createGroup() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая группа'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название группы'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final roomId = await _client.createRoom(
      name: name,
      preset: matrix.CreateRoomPreset.privateChat,
    );
    final room = _client.getRoomById(roomId);
    if (room != null) {
      // Участников добавляют через поиск сотрудника → room.invite(userId).
      setState(() => _selectedRoom = room);
    }
  }

  // «Удалить чат»: локальное скрытие для меня (clearChat). Комнату не покидаю,
  // историю на сервере не трогаю. У собеседника чат и переписка остаются.
  // При новом сообщении чат сам вернётся в список — но уже пустым для меня.
  Future<void> _deleteChat(matrix.Room room) async {
    final title = room.getLocalizedDisplayname();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          'Чат «$title» пропадёт из списка, а переписка скроется у вас. '
          'У собеседника всё останется. При новом сообщении чат вернётся пустым.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить чат'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.matrixService.clearChat(room.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось удалить чат: $e')));
      }
      return;
    }
    if (!mounted) return;
    if (_selectedRoom?.id == room.id) {
      setState(() => _selectedRoom = null);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          SizedBox(
            width: 360,
            child: Column(
              children: [
                _header(),
                _searchBar(),
                Expanded(child: _roomList()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedRoom == null
                ? _emptyPlaceholder()
                : ChatPanel(
                    key: ValueKey(_selectedRoom!.id),
                    room: _selectedRoom!,
                    service: widget.matrixService,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final me = _client.userID ?? '';
    return Container(
      color: kAccent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<matrix.Profile>(
              future: _client.fetchOwnProfile(),
              builder: (_, snap) => Text(
                snap.data?.displayName ?? me,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Новая группа',
            icon: const Icon(Icons.group_add, color: Colors.white70, size: 20),
            onPressed: _createGroup,
          ),
          IconButton(
            tooltip: 'Найти сотрудника или группу',
            icon: const Icon(
              Icons.person_add_alt,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: _openNewChatSearch,
          ),
          IconButton(
            tooltip: 'Мои сеансы',
            icon: const Icon(Icons.devices, color: Colors.white70, size: 20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionsScreen(
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
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout, color: Colors.white54, size: 20),
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.all(8),
    child: TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Поиск по чатам',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _searchController.clear(),
              )
            : null,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
  );

  Widget _roomList() {
    return StreamBuilder(
      stream: _client.onSync.stream,
      builder: (context, snapshot) {
        // Показываем только joined-комнаты, которые не «удалены» (скрыты).
        // Приглашения автоматически принимаются в MatrixService.
        var rooms = _client.rooms
            .where((r) => r.membership == matrix.Membership.join)
            .where((r) => widget.matrixService.isRoomVisible(r))
            .toList();
        if (_searchQuery.isNotEmpty) {
          rooms = rooms
              .where(
                (r) => r.getLocalizedDisplayname().toLowerCase().contains(
                  _searchQuery,
                ),
              )
              .toList();
        }
        if (rooms.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isNotEmpty
                  ? 'Ничего не найдено'
                  : 'Нет активных чатов',
              style: const TextStyle(color: Colors.black45, fontSize: 13),
            ),
          );
        }
        return ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index];
            final unread = room.notificationCount;
            final isSelected = _selectedRoom?.id == room.id;
            final title = room.getLocalizedDisplayname();
            final lastMsg = room.lastEvent?.body ?? 'Нет сообщений';

            // Правый клик (десктоп) — удалить чат.
            return GestureDetector(
              onSecondaryTap: () => _deleteChat(room),
              child: ListTile(
                selected: isSelected,
                selectedTileColor: const Color(0xFFF0F6F4),
                leading: InitialsAvatar(name: title, group: !room.isDirectChat),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  lastMsg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
                trailing: unread > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : null,
                onTap: () => setState(() => _selectedRoom = room),
                // Долгое нажатие — удалить чат (для тач/мыши).
                onLongPress: () => _deleteChat(room),
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyPlaceholder() => Container(
    color: const Color(0xFFF0F2F5),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 96, color: Colors.black26),
          SizedBox(height: 16),
          Text(
            'Выберите чат или найдите сотрудника',
            style: TextStyle(color: Colors.black45),
          ),
        ],
      ),
    ),
  );
}
