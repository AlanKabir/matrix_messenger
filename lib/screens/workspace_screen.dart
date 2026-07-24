// screens/workspace_screen.dart — двухпанельный workspace в стиле SGO.
// Сверху боковой панели: «Новая группа». ЕДИНЫЙ поиск (как WhatsApp Desktop):
// печатаешь в строке поиска — список чатов сменяется результатами:
//   «Чаты и группы» — мои комнаты по названию;
//   «Люди»          — каталог сервера; в плитке только ФИО (без @id).
//
// ЭКОНОМИЯ ЗАПРОСОВ К СЕРВЕРУ: запрос уходит ПОЛНЫМ введённым словом и
// только после паузы 500 мс (debounce) — не на каждую букву. Если сервер
// отдал полный список (не обрезал по лимиту), дописывание букв фильтруется
// ЛОКАЛЬНО без новых запросов.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import '../widgets/member_picker.dart';
import 'chat_panel.dart';
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

  // --- поиск по каталогу сотрудников (раздел «Люди») ---
  Timer? _dirDebounce;
  bool _dirLoading = false;
  List<matrix.Profile> _dirResults = [];
  String? _dirError;

  // Кэш каталога: по какому префиксу загружен и полон ли ответ сервера.
  // Пока новый запрос начинается с этого префикса и кэш полный —
  // фильтруем локально и НЕ ходим на сервер.
  String? _dirCacheQuery;
  List<matrix.Profile> _dirCache = [];
  bool _dirCacheComplete = false;

  // --- индикатор соединения ---
  // true, пока синхронизация с сервером проходит успешно. При ошибке
  // показываем плашку «нет связи» и пишем в лог DNS-снимок (какой IP
  // машина видит для matrix.sgo.kz в момент сбоя).
  bool _online = true;
  StreamSubscription<matrix.SyncStatusUpdate>? _statusSub;
  DateTime? _lastDnsLog;

  @override
  void initState() {
    super.initState();
    _client = widget.matrixService.client!;
    _ownProfile = _client.fetchOwnProfile();
    // Подключаем уведомления/трей к текущему клиенту.
    DesktopService.instance.attachClient(_client);
    _searchController.addListener(_onSearchChanged);
    // Перерисовываем ВЕСЬ экран после каждой синхронизации: при холодном
    // старте имена, участники групп и последние сообщения доезжают с
    // сервера через несколько секунд — без этого интерфейс обновлялся
    // только после клика мышью.
    _syncSub = _client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
    // Следим за состоянием синхронизации: ошибка → плашка «нет связи»
    // + DNS-снимок в лог (главная улика при проблемах с DNS-кэшем).
    _statusSub = _client.onSyncStatus.stream.listen((update) {
      final ok = update.status != matrix.SyncStatus.error;
      if (ok != _online && mounted) setState(() => _online = ok);
      if (!ok) _logDnsSnapshot(update.error?.toString());
    });
    // Прогрев: после первой синхронизации дотягиваем участников видимых
    // комнат, чтобы имена в списке сразу стали полными («Кани Каиржан…»
    // вместо «K Kani» из кэша).
    _warmUpRooms();
  }

  Future<void> _warmUpRooms() async {
    try {
      // При восстановленной сессии комнаты уже в локальной базе — ждать
      // синхронизацию не нужно. Ждём её только если список ещё пуст
      // (самый первый вход, база пустая).
      if (_client.rooms.isEmpty) {
        await _client.onSync.stream.first;
      }
      final rooms = _client.rooms.take(30).toList();
      for (var i = 0; i < rooms.length; i++) {
        final room = rooms[i];
        try {
          // Дочитать состояние комнаты (участников, имена) из базы...
          await room.postLoad();
          // ...и дотянуть недостающих участников с сервера.
          await room.requestParticipants();
        } catch (_) {}
        // Перерисовываем каждые 3 комнаты, а не одним махом в конце —
        // полные ФИО появляются сразу, без клика по интерфейсу.
        if (mounted && (i % 3 == 2 || i == rooms.length - 1)) {
          setState(() {});
        }
      }
    } catch (_) {}
  }

  StreamSubscription<matrix.SyncUpdate>? _syncSub;

  @override
  void dispose() {
    _syncSub?.cancel();
    _statusSub?.cancel();
    _dirDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // В момент сбоя синхронизации пишем в лог, какой IP машина СЕЙЧАС видит
  // для matrix.sgo.kz. Если там окажется старый сервер — это улика, что
  // проблема в DNS-кэше/DNS-сервере, а не в приложении.
  // Не чаще раза в минуту, чтобы не засорять лог при длительном сбое.
  Future<void> _logDnsSnapshot(String? error) async {
    final now = DateTime.now();
    if (_lastDnsLog != null &&
        now.difference(_lastDnsLog!) < const Duration(minutes: 1)) {
      return;
    }
    _lastDnsLog = now;
    try {
      final ips = await InternetAddress.lookup('matrix.sgo.kz');
      final list = ips.map((a) => a.address).join(', ');
      debugPrint('SYNC ERROR: $error | DNS matrix.sgo.kz -> $list');
    } catch (e) {
      debugPrint('SYNC ERROR: $error | DNS lookup failed: $e');
    }
  }

  // Локальная фильтрация кэша каталога (по ФИО и по логину).
  List<matrix.Profile> _filterCache(String q) => _dirCache
      .where(
        (p) =>
            (p.displayName ?? '').toLowerCase().contains(q) ||
            p.userId.toLowerCase().contains(q),
      )
      .toList();

  // Изменился текст в строке поиска.
  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() => _searchQuery = q);
    _dirDebounce?.cancel();

    // Пусто или 1 буква — каталог не спрашиваем (слишком общий запрос).
    if (q.length < 2) {
      setState(() {
        _dirResults = [];
        _dirLoading = false;
        _dirError = null;
      });
      return;
    }

    // Запрос продолжает уже загруженное слово, и сервер тогда отдал ВСЁ
    // (не обрезал по лимиту) — фильтруем локально, БЕЗ запроса к серверу.
    if (_dirCacheQuery != null &&
        q.startsWith(_dirCacheQuery!) &&
        _dirCacheComplete) {
      setState(() {
        _dirResults = _filterCache(q);
        _dirLoading = false;
        _dirError = null;
      });
      return;
    }

    // Один запрос ПОЛНЫМ введённым словом после паузы 500 мс.
    // Пока человек печатает без пауз — запросы не уходят вовсе.
    setState(() => _dirLoading = true);
    _dirDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchDirectory(q);
    });
  }

  // Один запрос к каталогу с тем словом, которое ввёл пользователь.
  Future<void> _fetchDirectory(String q) async {
    try {
      final response = await _client.searchUserDirectory(q, limit: 100);
      if (!mounted) return;
      _dirCacheQuery = q;
      _dirCache = response.results;
      // limited == true значит сервер обрезал список — кэш неполный,
      // при дописывании букв придётся спросить сервер ещё раз.
      _dirCacheComplete = response.limited != true;

      final current = _searchController.text.trim().toLowerCase();
      if (current.length < 2) {
        setState(() {
          _dirResults = [];
          _dirLoading = false;
          _dirError = null;
        });
      } else if (current == q) {
        // Показываем ответ сервера как есть.
        setState(() {
          _dirResults = response.results;
          _dirLoading = false;
          _dirError = null;
        });
      } else if (current.startsWith(q) && _dirCacheComplete) {
        // Успели дописать буквы, но кэш полный — фильтруем локально.
        setState(() {
          _dirResults = _filterCache(current);
          _dirLoading = false;
          _dirError = null;
        });
      } else {
        // Запрос изменился сильнее — спрашиваем сервер по актуальному слову.
        _fetchDirectory(current);
      }
    } catch (e) {
      // Например, rate-limit сервера. Показываем ошибку честно + кэш, если есть.
      // И пишем DNS-снимок в лог: сбои поиска не задевают sync (он живёт на
      // уже открытом соединении), поэтому без этой строки они оставались
      // незадокументированными.
      _logDnsSnapshot('user_directory search failed: $e');
      if (mounted) {
        setState(() {
          _dirResults = _filterCache(
            _searchController.text.trim().toLowerCase(),
          );
          _dirLoading = false;
          _dirError = 'Поиск временно недоступен, попробуйте ещё раз';
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
  }

  // Клик по человеку из раздела «Люди»: создать (или открыть) личный чат.
  Future<void> _openDirectChat(String userId) async {
    try {
      final room = await widget.matrixService.startDirectChat(userId);
      if (!mounted) return;
      if (room != null) {
        _clearSearch();
        setState(() => _selectedRoom = room);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось начать чат: $e')));
      }
    }
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
            child: const Text('Далее'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    // Шаг 2 — выбор участников (себя в списке не показываем).
    final members = await showMemberPicker(
      context,
      _client,
      title: 'Кого добавить в «$name»',
      confirmLabel: 'Создать группу',
      exclude: {_client.userID ?? ''},
    );
    if (members == null || members.isEmpty || !mounted) return;

    try {
      final roomId = await _client.createRoom(
        name: name,
        preset: matrix.CreateRoomPreset.privateChat,
        invite: members,
      );
      final room = _client.getRoomById(roomId);
      if (room != null && mounted) {
        setState(() => _selectedRoom = room);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Группа создана, приглашено: ${members.length}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать группу: $e')),
        );
      }
    }
  }

  // Контекстное меню чата в списке (правый клик / долгое нажатие).
  Future<void> _roomMenu(matrix.Room room, Offset pos) async {
    final isGroup = !room.isDirectChat;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (isGroup)
          const PopupMenuItem(value: 'add', child: Text('Добавить участников')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Удалить чат', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'add':
        await _addMembers(room);
        break;
      case 'delete':
        await _deleteChat(room);
        break;
    }
  }

  // Добавление людей в уже существующую группу.
  Future<void> _addMembers(matrix.Room room) async {
    final already = room.getParticipants().map((u) => u.id).toSet();
    final members = await showMemberPicker(
      context,
      _client,
      title: 'Добавить в «${room.getLocalizedDisplayname()}»',
      confirmLabel: 'Добавить',
      exclude: already,
    );
    if (members == null || members.isEmpty || !mounted) return;

    int ok = 0;
    final List<String> failed = [];
    for (final id in members) {
      try {
        await room.invite(id);
        ok++;
      } catch (_) {
        failed.add(id);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? 'Приглашено: $ok'
              : 'Приглашено: $ok, не удалось: ${failed.length}',
        ),
      ),
    );
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
                  Expanded(
                    child: _searchQuery.isEmpty
                        ? _roomList()
                        : _searchResults(),
                  ),
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
        const Text(
          'Чаты',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: T.accent,
            letterSpacing: -0.2,
          ),
        ),
        // Плашка появляется ТОЛЬКО при сбое синхронизации.
        if (!_online)
          Container(
            margin: const EdgeInsets.only(left: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF5C6C0)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 14, color: Color(0xFFC62828)),
                SizedBox(width: 4),
                Text(
                  'нет связи',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC62828),
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
        IconButton(
          tooltip: 'Новая группа',
          icon: const Icon(Icons.group_add, color: T.accent, size: 22),
          onPressed: _createGroup,
        ),
      ],
    ),
  );

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: CallbackShortcuts(
      bindings: {
        // Esc — очистить поиск и вернуться к списку чатов.
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Поиск сотрудника или чата',
          hintStyle: const TextStyle(color: T.hint, fontSize: 14),
          prefixIcon: const Icon(Icons.search, size: 20, color: T.hint),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _clearSearch,
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
    ),
  );

  // ---------------------------------------------------------------------------
  // Обычный список чатов (поиск пустой).
  Widget _roomList() {
    return StreamBuilder(
      stream: _client.onSync.stream,
      builder: (context, snapshot) {
        final rooms = _visibleRooms();
        if (rooms.isEmpty) {
          return const Center(
            child: Text(
              'Нет активных чатов',
              style: TextStyle(color: T.textSec, fontSize: 13),
            ),
          );
        }
        return ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (context, index) => _roomTile(rooms[index]),
        );
      },
    );
  }

  // Мои видимые комнаты (joined + не скрытые «удалением чата»).
  List<matrix.Room> _visibleRooms() => _client.rooms
      .where((r) => r.membership == matrix.Membership.join)
      .where((r) => widget.matrixService.isRoomVisible(r))
      .toList();

  // ---------------------------------------------------------------------------
  // Результаты поиска (как в WhatsApp Desktop): «Чаты и группы» + «Люди».
  Widget _searchResults() {
    // 1) Мои чаты и группы, подходящие по названию.
    final rooms = _visibleRooms()
        .where(
          (r) =>
              r.getLocalizedDisplayname().toLowerCase().contains(_searchQuery),
        )
        .toList();

    // ID собеседников, с которыми уже есть личный чат, — чтобы не дублировать
    // их в разделе «Люди».
    final haveDirect = <String>{};
    for (final r in _visibleRooms()) {
      if (r.isDirectChat && r.directChatMatrixID != null) {
        haveDirect.add(r.directChatMatrixID!);
      }
    }

    // 2) Люди из каталога: без себя и без тех, кто уже в «Чатах».
    final me = _client.userID;
    final people = _dirResults
        .where((p) => p.userId != me && !haveDirect.contains(p.userId))
        .toList();

    // Сортировка: сервер матчит ЛЮБОЕ слово имени («Ка» находит и Калиева,
    // и Кайрата Канатовича по имени/отчеству). Показываем в порядке:
    //   0 — фамилия начинается с запроса (первое слово: «Фамилия Имя Отчество»)
    //   1 — имя или отчество начинается с запроса
    //   2 — совпадение где-то внутри слова
    // Внутри групп — по алфавиту.
    int rankOf(matrix.Profile p) {
      final name = (p.displayName ?? p.userId).toLowerCase();
      if (name.startsWith(_searchQuery)) return 0;
      final words = name.split(RegExp(r'\s+'));
      for (var i = 1; i < words.length; i++) {
        if (words[i].startsWith(_searchQuery)) return 1;
      }
      return 2;
    }

    people.sort((a, b) {
      final r = rankOf(a).compareTo(rankOf(b));
      if (r != 0) return r;
      return (a.displayName ?? a.userId).toLowerCase().compareTo(
        (b.displayName ?? b.userId).toLowerCase(),
      );
    });

    if (rooms.isEmpty && people.isEmpty && !_dirLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _dirError ??
                (_searchQuery.length < 2
                    ? 'Введите минимум 2 буквы'
                    : 'Ничего не найдено'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _dirError != null ? Colors.redAccent : T.textSec,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (rooms.isNotEmpty) ...[
          _sectionHeader('Чаты и группы'),
          ...rooms.map(_roomTile),
        ],
        if (people.isNotEmpty || _dirLoading) _sectionHeader('Люди'),
        if (_dirError != null && !_dirLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              _dirError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        if (_dirLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: T.accent,
                ),
              ),
            ),
          )
        else
          ...people.map(_personTile),
      ],
    );
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: T.steel,
        letterSpacing: 0.3,
      ),
    ),
  );

  // Плитка человека из каталога — только ФИО, без Matrix ID.
  Widget _personTile(matrix.Profile user) {
    final title = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : user.userId.split(':').first.replaceFirst('@', '');
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: InitialsAvatar(name: title, radius: 20),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, color: T.text),
        ),
        onTap: () => _openDirectChat(user.userId),
      ),
    );
  }

  // Плитка комнаты (используется и в списке чатов, и в результатах поиска).
  Widget _roomTile(matrix.Room room) {
    final unread = room.notificationCount;
    final isSelected = _selectedRoom?.id == room.id;
    final title = room.getLocalizedDisplayname();
    final lastMsg = room.lastEvent?.body ?? 'Нет сообщений';

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _roomMenu(room, d.globalPosition),
        child: ListTile(
          selected: isSelected,
          selectedTileColor: T.selected,
          leading: InitialsAvatar(name: title, group: !room.isDirectChat),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500, color: T.text),
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
          onTap: () {
            // Из результатов поиска: открыть чат и вернуть обычный список.
            if (_searchQuery.isNotEmpty) _clearSearch();
            setState(() => _selectedRoom = room);
          },
          onLongPress: () => _roomMenu(room, const Offset(200, 300)),
        ),
      ),
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

  // Заглушка правой части, пока чат не выбран: логотип в стиле
  // водяного знака (как герб на фоне чата).
  // НАСТРОЙКА: _opacity (0.1 еле видно … 0.5 отчётливо),
  //            _sizeFactor (доля от размера области).
  static const double _emptyOpacity = 0.35;
  static const double _emptySizeFactor = 0.45;

  static const List<double> _greyMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, // R
    0.2126, 0.7152, 0.0722, 0, 0, // G
    0.2126, 0.7152, 0.0722, 0, 0, // B
    0, 0, 0, 1, 0, // A
  ];

  Widget _emptyPlaceholder() => Container(
    color: T.feedBg,
    child: Center(
      child: FractionallySizedBox(
        widthFactor: _emptySizeFactor,
        heightFactor: _emptySizeFactor,
        child: Opacity(
          opacity: _emptyOpacity,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(_greyMatrix),
            child: Image.asset(
              'assets/emblem_title.png',
              fit: BoxFit.contain,
              // Если asset не подключён — прежняя заглушка с иконкой.
              errorBuilder: (_, _, _) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 96,
                    color: Color(0xFFC3CCDA),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Выберите чат или найдите сотрудника',
                    style: TextStyle(color: T.textSec),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
