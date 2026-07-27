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
    final others = room.receiptState.global.otherUsers;
    if (others.isNotEmpty) {
      final ts = event.originServerTs.millisecondsSinceEpoch;
      final readByAll = others.values.every(
        (r) => r.timestamp.millisecondsSinceEpoch >= ts,
      );
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
    return FutureBuilder<Uint8List?>(
      future: _loadAvatar(mxc, c),
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
Future<matrix.Room?> showForwardPicker(
  BuildContext context,
  matrix.Client client,
) {
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

        final rooms = client.rooms
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
                            final roomId = await client.startDirectChat(
                              u.userId,
                            );
                            final room = client.getRoomById(roomId);
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
