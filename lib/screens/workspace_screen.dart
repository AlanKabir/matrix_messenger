// screens/workspace_screen.dart — двухпанельный workspace в стиле SGO.
// Сверху боковой панели: «Новая группа» и «Найти сотрудника или группу».
// Снизу: строка профиля, открывающая экран «Настройки».

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import 'chat_panel.dart';
import 'new_chat_search_sheet.dart';
import 'settings_screen.dart';
import '../services/desktop_service.dart';

class WorkspaceScreen extends StatefulWidget {
  final MatrixService matrixService;
  const WorkspaceScreen({super.key, required this.matrixService});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final matrix.Client _client;
  late final Future<matrix.Profile> _ownProfile;
  matrix.Room? _selectedRoom;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _client = widget.matrixService.client!;
    _ownProfile = _client.fetchOwnProfile();
    // Подключаем уведомления/трей к текущему клиенту.
    DesktopService.instance.attachClient(_client);
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

  void _openNewChatSearch() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => NewChatSearchSheet(
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
      setState(() => _selectedRoom = room);
    }
  }

  // «Удалить чат»: локальное скрытие для меня (clearChat). Комнату не покидаю,
  // историю на сервере не трогаю. При новом сообщении чат вернётся пустым.
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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(service: widget.matrixService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Container(
              color: T.panel,
              child: Column(
                children: [
                  _header(),
                  _searchBar(),
                  Expanded(child: _roomList()),
                  _profileTile(),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: T.border),
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

  Widget _header() => Container(
    color: T.panel,
    padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Чаты',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: T.accent,
              letterSpacing: -0.2,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Новая группа',
          icon: const Icon(Icons.group_add, color: T.accent, size: 22),
          onPressed: _createGroup,
        ),
        IconButton(
          tooltip: 'Найти сотрудника или группу',
          icon: const Icon(Icons.person_add_alt, color: T.accent, size: 22),
          onPressed: _openNewChatSearch,
        ),
      ],
    ),
  );

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Поиск',
        hintStyle: const TextStyle(color: T.hint, fontSize: 14),
        prefixIcon: const Icon(Icons.search, size: 20, color: T.hint),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _searchController.clear(),
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFE6EBF3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _roomList() {
    return StreamBuilder(
      stream: _client.onSync.stream,
      builder: (context, snapshot) {
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
              style: const TextStyle(color: T.textSec, fontSize: 13),
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

            return Material(
              color: Colors.transparent,
              child: GestureDetector(
                onSecondaryTap: () => _deleteChat(room),
                child: ListTile(
                  selected: isSelected,
                  selectedTileColor: T.selected,
                  leading: InitialsAvatar(
                    name: title,
                    group: !room.isDirectChat,
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: T.text,
                    ),
                  ),
                  subtitle: Text(
                    lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: T.textSec),
                  ),
                  trailing: unread > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: T.unreadBadge,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: T.unreadBadgeText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => setState(() => _selectedRoom = room),
                  onLongPress: () => _deleteChat(room),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Строка профиля внизу боковой панели → открывает «Настройки».
  Widget _profileTile() {
    final me = _client.userID ?? '';
    return Material(
      color: T.panel,
      child: InkWell(
        onTap: _openSettings,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: T.border)),
          ),
          child: Row(
            children: [
              FutureBuilder<matrix.Profile>(
                future: _ownProfile,
                builder: (_, snap) => InitialsAvatar(
                  name: snap.data?.displayName ?? me,
                  radius: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FutureBuilder<matrix.Profile>(
                  future: _ownProfile,
                  builder: (_, snap) => Text(
                    snap.data?.displayName ?? me,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: T.text,
                    ),
                  ),
                ),
              ),
              const Icon(Icons.settings, color: T.hint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyPlaceholder() => Container(
    color: T.feedBg,
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 96, color: Color(0xFFC3CCDA)),
          SizedBox(height: 16),
          Text(
            'Выберите чат или найдите сотрудника',
            style: TextStyle(color: T.textSec),
          ),
        ],
      ),
    ),
  );
}
