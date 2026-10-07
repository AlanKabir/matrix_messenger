// widgets/common.dart — галочки, аватары, выбор получателя пересылки.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';

// Единый источник цвета — палитра T. kAccent оставлен для обратной
// совместимости со старым кодом, который на него ссылается.
const kAccent = T.accent;
const kTickGray = T.tickSent;
const kTickBlue = T.tickRead;

/// Статус собственного сообщения в терминах Matrix:
///  -1 — отправляется (часы), -2 — ошибка,
///   0 — на сервере (1 серая), 2 — прочитано собеседником(ами) (2 синие).
int ownEventStatus(matrix.Event event, matrix.Room room) {
  if (event.status.isSending) return -1;
  if (event.status.isError) return -2;
  try {
    // «Прочитано» = прочитали ВСЕ участники, а не только те, у кого
    // уже есть отметка. Иначе в группе, где кто-то ни разу не открывал
    // чат, загорались синие галочки, хотя он ничего не видел.
    final me = room.client.userID;
    final members = room
        .getParticipants()
        .where((u) => u.id != me && u.membership == matrix.Membership.join)
        .map((u) => u.id)
        .toList();
    if (members.isNotEmpty) {
      final others = room.receiptState.global.otherUsers;
      final ts = event.originServerTs.millisecondsSinceEpoch;
      final readByAll = members.every((id) {
        final r = others[id];
        return r != null && r.timestamp.millisecondsSinceEpoch >= ts;
      });
      if (readByAll) return 2;
    }
  } catch (_) {
    // Если структура receiptState в вашей сборке иная — просто не
    // показываем «прочитано», сообщение остаётся с одной галочкой.
  }
  return 0;
}

class StatusTicks extends StatelessWidget {
  final int status;
  const StatusTicks({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case -2:
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
      case -1:
        return const Icon(Icons.schedule, size: 14, color: kTickGray);
      case 2:
        return const Icon(Icons.done_all, size: 15, color: kTickBlue);
      case 0:
      default:
        return const Icon(Icons.check, size: 15, color: kTickGray);
    }
  }
}

/// Кружок-аватар.
/// Если передана mxc-ссылка [mxcUrl] и [client] — показывает ФОТОГРАФИЮ.
/// Если фото нет (или не загрузилось) — инициалы на цветном фоне,
/// а для групп — иконка группы. Так один виджет обслуживает весь интерфейс.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool group;

  // Аватар из профиля пользователя (Profile.avatarUrl / User.avatarUrl)
  // или комнаты (Room.avatar). Формат mxc://…
  final Uri? mxcUrl;
  // Клиент нужен, чтобы скачать картинку с сервера (с авторизацией).
  final matrix.Client? client;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 20,
    this.group = false,
    this.mxcUrl,
    this.client,
  });

  // Кэш скачанных аватаров в памяти: ключ — mxc-ссылка.
  // Без него список чатов перекачивал бы картинки при каждой перерисовке.
  static final Map<String, Uint8List> _cache = {};

  // Загрузки «в полёте»: один и тот же Future отдаётся всем плиткам и
  // всем перерисовкам — запрос к серверу уходит ровно один раз.
  static final Map<String, Future<Uint8List?>> _inflight = {};

  // Неудачные загрузки (фото удалено, сервер вернул ошибку) и время
  // неудачи. Повторяем не раньше чем через 10 минут — иначе каждая
  // синхронизация запускала бы новый запрос для каждой плитки.
  static final Map<String, DateTime> _failed = {};
  static const Duration _retryAfter = Duration(minutes: 10);

  Future<Uint8List?> _loadOnce(Uri mxc, matrix.Client c) {
    final key = mxc.toString();
    return _inflight.putIfAbsent(key, () async {
      try {
        final bytes = await _loadAvatar(mxc, c);
        if (bytes == null) _failed[key] = DateTime.now();
        return bytes;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  // Стабильный цвет по имени: одинаковое имя всегда одного цвета.
  Color _colorFor(String key) {
    if (key.isEmpty) return T.accent;
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return T.avatarColors[hash % T.avatarColors.length];
  }

  Future<Uint8List?> _loadAvatar(Uri mxc, matrix.Client c) async {
    final key = mxc.toString();
    final cached = _cache[key];
    if (cached != null) return cached;

    // Разбираем mxc://<сервер>/<id> и качаем миниатюру напрямую через
    // http-клиент SDK (он уже доверяет нашему внутреннему CA).
    final server = mxc.host;
    final mediaId = mxc.pathSegments.isNotEmpty ? mxc.pathSegments.last : '';
    final hs = c.homeserver?.toString().replaceAll(RegExp(r'/+$'), '');
    if (hs == null || server.isEmpty || mediaId.isEmpty) return null;

    final token = c.accessToken;
    const params = 'width=128&height=128&method=crop';
    // Сначала современный (авторизованный) путь, потом старый —
    // какой поддерживает сервер, тот и сработает.
    final urls = <String>[
      '$hs/_matrix/client/v1/media/thumbnail/$server/$mediaId?$params',
      '$hs/_matrix/media/v3/thumbnail/$server/$mediaId?$params',
    ];
    for (final u in urls) {
      try {
        final resp = await c.httpClient.get(
          Uri.parse(u),
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        );
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          _cache[key] = resp.bodyBytes;
          return resp.bodyBytes;
        }
      } catch (_) {
        // пробуем следующий адрес
      }
    }
    return null;
  }

  // Кружок без фото: иконка группы или инициалы.
  Widget _fallback() {
    if (group) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: T.accent,
        child: Icon(Icons.group, color: Colors.white, size: radius),
      );
    }
    final initials = name
        .replaceAll(RegExp(r'^@'), '')
        .split(RegExp(r'[\s:._@-]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colorFor(name),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(color: Colors.white, fontSize: radius * 0.7),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mxc = mxcUrl;
    final c = client;
    if (mxc == null || c == null) return _fallback();
    final key = mxc.toString();

    // Уже в кэше — рисуем фото СРАЗУ, без FutureBuilder: иначе на каждой
    // синхронизации кружок на долю секунды мигал инициалами.
    final cached = _cache[key];
    if (cached != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _colorFor(name),
        backgroundImage: MemoryImage(cached),
      );
    }
    // Недавно не загрузилось — не долбим сервер, показываем инициалы.
    final failedAt = _failed[key];
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryAfter) {
      return _fallback();
    }
    return FutureBuilder<Uint8List?>(
      future: _loadOnce(mxc, c),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return _fallback();
        return CircleAvatar(
          radius: radius,
          backgroundColor: _colorFor(name),
          backgroundImage: MemoryImage(bytes),
        );
      },
    );
  }
}

/// Выбор комнаты для пересылки: существующие чаты + поиск сотрудника
/// по каталогу Synapse (user_directory включен).
///
/// [openDirect] — как открыть личный чат с найденным сотрудником.
/// Передавайте MatrixService.startDirectChat: он не плодит дубли и создаёт
/// комнату БЕЗ шифрования (требование аудита). Запасной вариант без него
/// тоже отключает шифрование, но дубли не отсекает.
Future<matrix.Room?> showForwardPicker(
  BuildContext context,
  matrix.Client client, {
  Future<matrix.Room?> Function(String userId)? openDirect,
}) {
  String query = '';
  List<matrix.Profile> found = const [];
  bool searching = false;

  return showDialog<matrix.Room>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> runSearch(String q) async {
          if (q.trim().length < 2) {
            setState(() => found = const []);
            return;
          }
          setState(() => searching = true);
          try {
            final resp = await client.searchUserDirectory(q, limit: 15);
            setState(() => found = resp.results);
          } catch (_) {
          } finally {
            setState(() => searching = false);
          }
        }

        // Только комнаты, где я участник: в приглашение переслать нельзя.
        final rooms = client.rooms
            .where((r) => r.membership == matrix.Membership.join)
            .where(
              (r) =>
                  query.isEmpty ||
                  r.getLocalizedDisplayname().toLowerCase().contains(query),
            )
            .toList();

        return AlertDialog(
          title: const Text('Переслать сообщение'),
          content: SizedBox(
            width: 440,
            height: 500,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Чат или сотрудник...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    setState(() => query = v.toLowerCase());
                    runSearch(v);
                  },
                ),
                const SizedBox(height: 8),
                if (searching) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: ListView(
                    children: [
                      for (final r in rooms)
                        ListTile(
                          dense: true,
                          leading: InitialsAvatar(
                            name: r.getLocalizedDisplayname(),
                            radius: 16,
                            group: !r.isDirectChat,
                            mxcUrl: r.avatar,
                            client: client,
                          ),
                          title: Text(r.getLocalizedDisplayname()),
                          onTap: () => Navigator.of(ctx).pop(r),
                        ),
                      if (found.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Сотрудники',
                            style: TextStyle(fontSize: 12, color: T.textSec),
                          ),
                        ),
                      for (final u in found)
                        ListTile(
                          dense: true,
                          leading: InitialsAvatar(
                            name: u.displayName ?? u.userId,
                            radius: 16,
                            mxcUrl: u.avatarUrl,
                            client: client,
                          ),
                          // Matrix ID пользователю не показываем — только ФИО.
                          title: Text(u.displayName ?? u.userId),
                          onTap: () async {
                            matrix.Room? room;
                            try {
                              if (openDirect != null) {
                                room = await openDirect(u.userId);
                              } else {
                                final roomId = await client.startDirectChat(
                                  u.userId,
                                  enableEncryption: false,
                                  waitForSync: true,
                                );
                                room = client.getRoomById(roomId);
                              }
                            } catch (_) {}
                            if (ctx.mounted) Navigator.of(ctx).pop(room);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
          ],
        );
      },
    ),
  );
}
