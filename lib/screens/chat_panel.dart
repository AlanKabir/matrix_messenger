// screens/chat_panel.dart — окно переписки в стиле SGO (сине-золотой).
// Каркас: шапка (с поиском по чату), планка закреплённых, лента, композер.
// Пузырь сообщения → widgets/message_bubble.dart
// Поле ввода (+ reply/edit/Ctrl+V) → widgets/message_composer.dart
//
// НОВОЕ:
//  • Закреплённые сообщения (m.room.pinned_events): планка над лентой,
//    список всех закреплённых, закрепить/открепить из меню пузыря.
//  • Поиск по переписке: лупа в шапке, результаты поверх ленты,
//    кнопка «Искать в более ранних» подгружает историю.
//  • Прыжок к сообщению с подсветкой: из результатов поиска, из планки
//    закреплённых и по клику на цитату ответа (reply).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import 'group_info_screen.dart';

class ChatPanel extends StatefulWidget {
  final matrix.Room room;
  final MatrixService service;

  const ChatPanel({super.key, required this.room, required this.service});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late Future<matrix.Timeline> _timelineFuture;
  matrix.Timeline? _timeline;

  // Композер: через этот ключ пузыри запускают ответ/редактирование,
  // а drag-and-drop отдаёт файлы на отправку.
  final GlobalKey<MessageComposerState> _composerKey =
      GlobalKey<MessageComposerState>();

  // Прокрутка ленты с возможностью прыжка к произвольному сообщению.
  final ItemScrollController _itemScroll = ItemScrollController();

  // Последний построенный список событий (нужен для поиска индекса
  // при прыжке и для локального поиска по переписке).
  List<matrix.Event> _lastEvents = const [];

  // Подсветка сообщения после прыжка.
  String? _highlightId;
  Timer? _highlightTimer;

  // Поиск по переписке.
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _searchLoadingMore = false;

  // true, пока файл «висит» над областью чата (для подсветки).
  bool _dragging = false;

  // Защита от повторных запросов «прочитано» на каждое обновление ленты.
  bool _markingRead = false;

  void _loadTimeline() {
    _timeline = null;
    _timelineFuture = widget.room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
        // Чат открыт — значит сообщения прочитаны. Без этого счётчик
        // непрочитанных не сбрасывался, пока не переключишь чат.
        _markRead();
      },
    );
    _timelineFuture.then((t) {
      _timeline = t;
      t.setReadMarker();
    });
    // Synapse присылает состав комнаты лениво (только тех, кто недавно писал).
    // Запрашиваем полный список участников явно — иначе в группе видно
    // «3 участника» вместо реальных пяти, пока остальные не напишут.
    _refreshParticipants();
  }

  // Ставит отметку «прочитано» — только когда есть что сбрасывать,
  // чтобы не дёргать сервер лишними запросами.
  void _markRead() {
    if (_markingRead) return;
    if (widget.room.notificationCount == 0) return;
    final tl = _timeline;
    if (tl == null) return;
    _markingRead = true;
    tl.setReadMarker().whenComplete(() {
      _markingRead = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshParticipants() async {
    try {
      await widget.room.postLoad();
    } catch (_) {}
    try {
      await widget.room.requestParticipants();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadTimeline();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _searchQuery && mounted) setState(() => _searchQuery = q);
    });
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _composerKey.currentState?.cancelContext();
      _closeSearch();
      _loadTimeline();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Прыжок к сообщению + подсветка.

  void _flash(String eventId) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = eventId);
    _highlightTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _jumpTo(String eventId) async {
    final tl = _timeline;
    if (tl == null) return;
    for (var attempt = 0; attempt < 12; attempt++) {
      final idx = _lastEvents.indexWhere((e) => e.eventId == eventId);
      if (idx != -1) {
        _flash(eventId);
        if (_itemScroll.isAttached) {
          await _itemScroll.scrollTo(
            index: idx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.4,
          );
        }
        return;
      }
      // Сообщение ещё не загружено — тянем историю порциями.
      if (!tl.canRequestHistory) break;
      try {
        await tl.requestHistory(historyCount: 100);
      } catch (_) {
        break;
      }
      if (mounted) setState(() {});
      // Даём кадру перестроиться, чтобы _lastEvents обновился.
      await Future.delayed(const Duration(milliseconds: 60));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось найти сообщение в истории')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Поиск по переписке.

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
    });
  }

  List<matrix.Event> _searchMatches() {
    if (_searchQuery.length < 2) return const [];
    return _lastEvents
        .where(
          (e) =>
              stripReplyFallback(e.body).toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  Future<void> _searchLoadMore() async {
    final tl = _timeline;
    if (tl == null || !tl.canRequestHistory || _searchLoadingMore) return;
    setState(() => _searchLoadingMore = true);
    try {
      await tl.requestHistory(historyCount: 200);
    } catch (_) {}
    if (mounted) setState(() => _searchLoadingMore = false);
  }

  // ---------------------------------------------------------------------------
  // Закреплённые.

  Future<void> _unpin(String eventId) async {
    try {
      final ids = List<String>.from(widget.room.pinnedEventIds)
        ..remove(eventId);
      await widget.room.setPinnedEvents(ids);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открепить (нет прав в этой группе)'),
          ),
        );
      }
    }
  }

  // Список всех закреплённых (нижняя шторка).
  void _showPinnedSheet() {
    final ids = widget.room.pinnedEventIds.reversed.toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: T.panelAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, size: 18, color: T.gold),
                  const SizedBox(width: 8),
                  Text(
                    'Закреплённые (${ids.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: T.accent,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: ids.length,
                itemBuilder: (_, i) => _pinnedTile(ctx, ids[i]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _pinnedTile(BuildContext sheetCtx, String eventId) {
    return FutureBuilder<matrix.Event?>(
      future: widget.room.getEventById(eventId),
      builder: (_, snap) {
        final e = snap.data;
        final name = e == null
            ? '…'
            : widget.room
                  .unsafeGetUserFromMemoryOrFallback(e.senderId)
                  .calcDisplayname();
        final text = e == null ? 'Загрузка…' : eventSnippet(e);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.push_pin_outlined, size: 18, color: T.hint),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          trailing: IconButton(
            tooltip: 'Открепить',
            icon: const Icon(Icons.close, size: 16, color: T.hint),
            onPressed: () {
              Navigator.pop(sheetCtx);
              _unpin(eventId);
            },
          ),
          onTap: () {
            Navigator.pop(sheetCtx);
            _jumpTo(eventId);
          },
        );
      },
    );
  }

  // Планка над лентой: последнее закреплённое.
  Widget _pinnedBar() {
    final ids = widget.room.pinnedEventIds;
    if (ids.isEmpty) return const SizedBox.shrink();
    final lastId = ids.last;
    return Material(
      color: T.panelAlt,
      child: InkWell(
        onTap: () => _jumpTo(lastId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: T.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 16, color: T.gold),
              const SizedBox(width: 10),
              Expanded(
                child: FutureBuilder<matrix.Event?>(
                  future: widget.room.getEventById(lastId),
                  builder: (_, snap) {
                    final e = snap.data;
                    return Text(
                      e == null ? 'Закреплённое сообщение' : eventSnippet(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: T.text),
                    );
                  },
                ),
              ),
              if (ids.length > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'ещё ${ids.length - 1}',
                    style: const TextStyle(fontSize: 12, color: T.steel),
                  ),
                ),
              IconButton(
                tooltip: 'Все закреплённые',
                icon: const Icon(Icons.list, size: 18, color: T.hint),
                onPressed: _showPinnedSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  // Обработка перетащенных файлов (может быть несколько сразу).
  // Приём через DropRegion (super_drag_and_drop) — тот же движок,
  // что и перетаскивание ИЗ чата, поэтому они не конфликтуют.
  Future<void> _onPerformDrop(PerformDropEvent event) async {
    int sent = 0;
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
      final done = Completer<void>();
      reader.getValue(
        Formats.fileUri,
        (uri) async {
          try {
            if (uri != null) {
              final f = File(uri.toFilePath());
              final bytes = await f.readAsBytes();
              final name = uri.pathSegments.isNotEmpty
                  ? Uri.decodeComponent(uri.pathSegments.last)
                  : 'file';
              if (bytes.isEmpty) {
                throw Exception('файл пустой или ещё не дописан на диск');
              }
              final ok = await _composerKey.currentState?.sendFile(bytes, name);
              if (ok == true) sent++;
            }
          } catch (e) {
            // Показываем настоящую причину — так понятно, что именно пошло не так
            // (занят другим приложением, нет прав, пустой файл и т.п.).
            debugPrint('DROP ERROR: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Не удалось отправить файл: $e')),
              );
            }
          } finally {
            if (!done.isCompleted) done.complete();
          }
        },
        onError: (e) {
          debugPrint('DROP READ ERROR: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Не удалось прочитать файл: $e')),
            );
          }
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;
    }
    if (mounted && sent > 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Отправлено файлов: $sent')));
    }
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

  // ---------------------------------------------------------------------------
  // Служебные события группы (как в WhatsApp): вошёл/вышел/пригласил/права.

  bool _isSystemEvent(matrix.Event e) {
    if (e.type == 'm.room.power_levels') return true;
    if (e.type != 'm.room.member') return false;
    // Показываем только СМЕНУ членства; смену имени/аватара — нет (шум).
    final now = e.content['membership'];
    final prev = e.prevContent?['membership'];
    return now != prev;
  }

  String _systemText(matrix.Event e) {
    String nameOf(String id) =>
        widget.room.unsafeGetUserFromMemoryOrFallback(id).calcDisplayname();
    if (e.type == 'm.room.power_levels') {
      return '${nameOf(e.senderId)} изменил(а) права в группе';
    }
    final target = e.stateKey ?? e.senderId;
    final t = nameOf(target);
    final s = nameOf(e.senderId);
    final now = e.content['membership'];
    final prev = e.prevContent?['membership'];
    switch (now) {
      case 'join':
        return '$t присоединился(-ась) к группе';
      case 'invite':
        return '$s пригласил(а) $t';
      case 'leave':
        if (e.senderId == target) {
          return prev == 'invite'
              ? '$t отклонил(а) приглашение'
              : '$t вышел(-ла) из группы';
        }
        return prev == 'invite'
            ? '$s отменил(а) приглашение $t'
            : '$s удалил(а) $t из группы';
      case 'ban':
        return '$s заблокировал(а) $t';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final title = room.getLocalizedDisplayname();
    final isGroup = !room.isDirectChat;

    return Column(
      children: [
        // ------ шапка ------
        Material(
          color: T.panelAlt,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: isGroup
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupInfoScreen(room: room),
                          ),
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: T.accent,
                                ),
                              ),
                              if (isGroup)
                                Text(
                                  '${room.getParticipants().length} участников',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: T.textSec,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (room.encrypted)
                          const Tooltip(
                            message: 'Сквозное шифрование включено',
                            child: Icon(Icons.lock, size: 16, color: T.accent),
                          ),
                        if (isGroup)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.chevron_right,
                              color: T.hint,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: _searchOpen ? 'Закрыть поиск' : 'Поиск по переписке',
                icon: Icon(
                  _searchOpen ? Icons.search_off : Icons.search,
                  color: T.accent,
                  size: 22,
                ),
                onPressed: _searchOpen ? _closeSearch : _openSearch,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        const Divider(height: 1, color: T.border),
        // ------ строка поиска по чату ------
        if (_searchOpen)
          Container(
            color: T.panelAlt,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Поиск в этом чате…',
                hintStyle: const TextStyle(color: T.hint, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20, color: T.hint),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _searchCtrl.clear,
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
        // ------ планка закреплённых ------
        _pinnedBar(),
        // ------ лента (с зоной приёма перетащенных файлов) ------
        Expanded(
          child: DropRegion(
            formats: const [Formats.fileUri],
            hitTestBehavior: HitTestBehavior.opaque,
            onDropOver: (event) {
              // Принимаем копирование файлов из Проводника.
              if (event.session.allowedOperations.contains(
                DropOperation.copy,
              )) {
                return DropOperation.copy;
              }
              return DropOperation.none;
            },
            onDropEnter: (_) => setState(() => _dragging = true),
            onDropLeave: (_) => setState(() => _dragging = false),
            onPerformDrop: (event) async {
              setState(() => _dragging = false);
              await _onPerformDrop(event);
            },
            child: Stack(
              children: [
                // Фон ленты.
                Positioned.fill(child: Container(color: T.feedBg)),
                // Водяной знак-герб.
                const Positioned.fill(child: _ChatWatermark()),
                // Лента сообщений.
                FutureBuilder<matrix.Timeline>(
                  future: _timelineFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: T.accent),
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
                    final timeline = snapshot.data!;
                    final clearedTs = widget.service.clearedTsFor(room.id);
                    final events = timeline.events.where((e) {
                      final afterClear =
                          clearedTs == null ||
                          e.originServerTs.millisecondsSinceEpoch > clearedTs;
                      if (!afterClear) return false;
                      final isMsg =
                          (e.relationshipEventId == null ||
                              e.relationshipType == 'm.in_reply_to') &&
                          !e.redacted &&
                          (e.type == 'm.room.message' ||
                              e.type == 'm.room.encrypted');
                      // Служебные надписи (вошёл/вышел/права) — только в группах.
                      final isSystem = isGroup && _isSystemEvent(e);
                      return isMsg || isSystem;
                    }).toList();
                    _lastEvents = events;
                    if (events.isEmpty) {
                      return const Center(
                        child: Text(
                          'Нет сообщений. Напишите первое.',
                          style: TextStyle(color: T.hint),
                        ),
                      );
                    }
                    return ScrollablePositionedList.builder(
                      reverse: true,
                      itemScrollController: _itemScroll,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 40,
                      ),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        // Служебное событие — маленькая надпись по центру.
                        if (_isSystemEvent(event)) {
                          return _SystemNotice(text: _systemText(event));
                        }
                        final isOwn =
                            event.senderId == widget.room.client.userID;
                        return MessageBubble(
                          event: event,
                          room: room,
                          timeline: timeline,
                          isOwn: isOwn,
                          showAuthor: isGroup && !isOwn,
                          senderName: _senderName(event),
                          highlighted: event.eventId == _highlightId,
                          onForward: () => _forward(event),
                          onReply: () =>
                              _composerKey.currentState?.startReply(event),
                          onEdit: (currentText) => _composerKey.currentState
                              ?.startEdit(event, currentText),
                          onJumpTo: _jumpTo,
                        );
                      },
                    );
                  },
                ),

                // Результаты поиска по чату (поверх ленты).
                if (_searchOpen && _searchQuery.length >= 2)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _searchResultsPanel(),
                  ),

                // Подсветка-подсказка, когда над чатом «висит» файл.
                if (_dragging)
                  Positioned.fill(
                    child: Container(
                      color: T.accent.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: T.panelAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: T.accent, width: 2),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.file_download_outlined,
                              size: 40,
                              color: T.accent,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Отпустите файл, чтобы отправить',
                              style: TextStyle(
                                color: T.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ------ композер (плашки ответа/редактирования внутри) ------
        MessageComposer(key: _composerKey, room: room),
      ],
    );
  }

  // Панель результатов поиска по чату.
  Widget _searchResultsPanel() {
    final matches = _searchMatches();
    final canMore = _timeline?.canRequestHistory ?? false;
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      decoration: BoxDecoration(
        color: T.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Text(
                  matches.isEmpty
                      ? 'Не найдено в загруженной истории'
                      : 'Найдено: ${matches.length}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: T.steel,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matches.length,
              itemBuilder: (_, i) {
                final e = matches[i];
                final ts = e.originServerTs;
                final when =
                    '${ts.day.toString().padLeft(2, '0')}.${ts.month.toString().padLeft(2, '0')} '
                    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
                return ListTile(
                  dense: true,
                  title: Text(
                    _senderName(e),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    stripReplyFallback(e.body),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: Text(
                    when,
                    style: const TextStyle(fontSize: 11, color: T.hint),
                  ),
                  onTap: () {
                    _closeSearch();
                    _jumpTo(e.eventId);
                  },
                );
              },
            ),
          ),
          if (canMore)
            TextButton.icon(
              onPressed: _searchLoadingMore ? null : _searchLoadMore,
              icon: _searchLoadingMore
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: Text(
                _searchLoadingMore
                    ? 'Загрузка…'
                    : 'Искать в более ранних сообщениях',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Служебная надпись в ленте («X присоединился», «Y удалил Z», …) —
// маленькая серая капсула по центру, как в WhatsApp.
class _SystemNotice extends StatelessWidget {
  final String text;
  const _SystemNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFDDE5F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: T.textSec),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Водяной знак-герб на фоне ленты чата.
// НАСТРОЙКА ВНЕШНЕГО ВИДА — два числа ниже:
//   _opacity — насколько заметен (0.05 еле видно … 0.15 отчётливо)
//   _sizeFactor — размер от высоты окна чата (0.5 = половина, 0.7 = крупнее)
class _ChatWatermark extends StatelessWidget {
  const _ChatWatermark();

  static const double _opacity = 0.12;
  static const double _sizeFactor = 0.6;

  // Матрица «обесцвечивания»: любой цвет герба → серый полутон,
  // прозрачность краёв (alpha) сохраняется.
  static const List<double> _greyMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, // R
    0.2126, 0.7152, 0.0722, 0, 0, // G
    0.2126, 0.7152, 0.0722, 0, 0, // B
    0, 0, 0, 1, 0, // A
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: _sizeFactor,
          heightFactor: _sizeFactor,
          child: Opacity(
            opacity: _opacity,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(_greyMatrix),
              child: Image.asset(
                'assets/emblem.png',
                fit: BoxFit.contain,
                // Если asset забыли подключить — просто ничего не рисуем,
                // чат работает как раньше.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
