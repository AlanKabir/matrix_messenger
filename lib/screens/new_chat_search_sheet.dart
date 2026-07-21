import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';

class NewChatSearchSheet extends StatefulWidget {
  final MatrixService service;
  final void Function(matrix.Room room) onChatOpened;

  const NewChatSearchSheet({
    super.key,
    required this.service,
    required this.onChatOpened,
  });

  @override
  State<NewChatSearchSheet> createState() => _NewChatSearchSheetState();
}

enum _SearchTab { people, groups }

class _NewChatSearchSheetState extends State<NewChatSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  _SearchTab _tab = _SearchTab.people;
  Timer? _debounce;

  bool _isLoading = false;
  String? _error;

  List<matrix.Profile> _userResults = [];
  List<matrix.PublishedRoomsChunk> _roomResults = [];

  matrix.Client get _client => widget.service.client!;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(query.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _userResults = [];
        _roomResults = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_tab == _SearchTab.people) {
        final response = await _client.searchUserDirectory(query, limit: 20);
        if (!mounted) return;
        setState(() => _userResults = response.results);
      } else {
        final response = await _client.queryPublicRooms(
          filter: matrix.PublicRoomQueryFilter(genericSearchTerm: query),
        );
        if (!mounted) return;
        setState(() => _roomResults = response.chunk);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Ошибка поиска: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startDirectChat(String userId) async {
    setState(() => _isLoading = true);
    try {
      final room = await widget.service.startDirectChat(userId);
      if (!mounted) return;
      if (room != null) {
        widget.onChatOpened(room);
      } else {
        setState(() => _error = 'Не удалось открыть чат');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось начать чат: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinRoom(String roomId) async {
    setState(() => _isLoading = true);
    try {
      await _client.joinRoom(roomId);
      final room = _client.getRoomById(roomId);
      if (!mounted) return;
      if (room != null) widget.onChatOpened(room);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось присоединиться: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5DBE2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _buildTabSwitcher(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onQueryChanged,
                style: const TextStyle(color: T.text),
                decoration: InputDecoration(
                  hintText: _tab == _SearchTab.people
                      ? 'Введите имя или логин...'
                      : 'Введите название группы...',
                  hintStyle: const TextStyle(color: T.hint),
                  prefixIcon: const Icon(Icons.search, color: T.hint),
                  filled: true,
                  fillColor: const Color(0xFFE6EBF3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildResultsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _tabButton('Люди', _SearchTab.people, Icons.person_outline),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tabButton(
              'Группы',
              _SearchTab.groups,
              Icons.groups_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, _SearchTab tab, IconData icon) {
    final isActive = _tab == tab;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = tab);
        _runSearch(_controller.text.trim());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? T.selected : const Color(0xFFF2F5F9),
          borderRadius: BorderRadius.circular(10),
          border: isActive ? Border.all(color: T.accent, width: 1) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isActive ? T.accent : T.hint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? T.accent : T.textSec,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: T.accent));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Text(
          'Начните вводить имя для поиска',
          style: TextStyle(color: T.hint, fontSize: 13),
        ),
      );
    }

    if (_tab == _SearchTab.people) {
      if (_userResults.isEmpty) {
        return const Center(
          child: Text('Никого не найдено', style: TextStyle(color: T.hint)),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _userResults.length,
        itemBuilder: (context, index) {
          final user = _userResults[index];
          final title = user.displayName?.isNotEmpty == true
              ? user.displayName!
              : user.userId;
          return ListTile(
            leading: InitialsAvatar(name: title, radius: 20),
            title: Text(title, style: const TextStyle(color: T.text)),
            subtitle: Text(
              user.userId,
              style: const TextStyle(color: T.textSec, fontSize: 12),
            ),
            onTap: () => _startDirectChat(user.userId),
          );
        },
      );
    } else {
      if (_roomResults.isEmpty) {
        return const Center(
          child: Text('Групп не найдено', style: TextStyle(color: T.hint)),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _roomResults.length,
        itemBuilder: (context, index) {
          final room = _roomResults[index];
          final title = room.name?.isNotEmpty == true
              ? room.name!
              : room.roomId;
          return ListTile(
            leading: InitialsAvatar(name: title, radius: 20, group: true),
            title: Text(title, style: const TextStyle(color: T.text)),
            subtitle: Text(
              '${room.numJoinedMembers} участников',
              style: const TextStyle(color: T.textSec, fontSize: 12),
            ),
            onTap: () => _joinRoom(room.roomId),
          );
        },
      );
    }
  }
}
