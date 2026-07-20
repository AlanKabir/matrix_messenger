// widgets/common.dart — галочки, аватары, выбор получателя пересылки.

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

const kAccent = Color(0xFF128C7E); // фирменный зеленый WhatsApp
const kTickGray = Color(0xFF8696A0);
const kTickBlue = Color(0xFF53BDEB);

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

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool group;
  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 20,
    this.group = false,
  });

  @override
  Widget build(BuildContext context) {
    if (group) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: kAccent,
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
      backgroundColor: kAccent,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(color: Colors.white, fontSize: radius * 0.7),
      ),
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
                          ),
                          title: Text(r.getLocalizedDisplayname()),
                          onTap: () => Navigator.of(ctx).pop(r),
                        ),
                      if (found.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Сотрудники',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      for (final u in found)
                        ListTile(
                          dense: true,
                          leading: InitialsAvatar(
                            name: u.displayName ?? u.userId,
                            radius: 16,
                          ),
                          title: Text(u.displayName ?? u.userId),
                          subtitle: Text(
                            u.userId,
                            style: const TextStyle(fontSize: 11),
                          ),
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
