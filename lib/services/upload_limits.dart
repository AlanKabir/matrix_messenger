// services/upload_limits.dart — лимит размера отправляемых файлов.
//
// КАК УСТРОЕНО
// • Жёсткий потолок для всех задаёт СЕРВЕР (max_upload_size в Synapse,
//   сейчас 50 МБ). Приложение узнаёт его у сервера само.
// • Внутри потолка лимит задаёт АДМИНИСТРАТОР:
//     – «по умолчанию для всех» (20 МБ);
//     – персонально отдельным сотрудникам (больше или меньше).
// • Настройки лежат в служебной комнате #abyroy-settings:<сервер> как
//   state-событие kz.sgo.upload_limits:
//       { "default_mb": 20, "users": { "@ivanov:matrix.sgo.kz": 50 } }
//   Писать туда может только админ (power level 100) — сервер отклонит
//   попытку любого другого. Все остальные только читают. В списке чатов
//   комната скрыта.
// • Админ = администратор сервера Synapse (тот, кто входит в synapse-admin).
//   Приложение спрашивает это у сервера, списка в коде нет.
// • Изменения доходят до сотрудников сразу, с ближайшей синхронизацией.
//
// ВАЖНО (ИБ): персональный лимит проверяет ПРИЛОЖЕНИЕ. Через API в обход
// приложения можно отправить файл до серверного потолка. Жёсткая граница —
// только max_upload_size на сервере.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

class UploadLimits extends ChangeNotifier {
  UploadLimits._();
  static final UploadLimits instance = UploadLimits._();

  /// Тип state-события с настройками.
  static const String stateType = 'kz.sgo.upload_limits';

  /// Локальная часть адреса служебной комнаты: #abyroy-settings:<сервер>.
  static const String aliasLocalpart = 'abyroy-settings';

  /// Лимит по умолчанию, пока админ ничего не настроил.
  static const int defaultLimitMb = 20;

  /// Нижняя граница ползунка.
  static const int minLimitMb = 5;

  /// Если сервер не ответил, какой у него потолок, — считаем 50 МБ
  /// (значение Synapse по умолчанию).
  static const int _fallbackServerCapMb = 50;

  static const int _mb = 1024 * 1024;

  matrix.Client? _client;
  StreamSubscription<matrix.SyncUpdate>? _syncSub;

  String? _roomId;
  DateTime? _lastResolve;
  bool _resolving = false;

  int _serverCapMb = _fallbackServerCapMb;
  bool _isAdmin = false;
  int _defaultMb = defaultLimitMb;
  Map<String, int> _users = {};

  // ─── Что читает интерфейс ─────────────────────────────────────────────────

  /// Потолок сервера в МБ (верхняя граница ползунка).
  int get serverCapMb => _serverCapMb;

  /// Текущий пользователь — администратор сервера.
  bool get isAdmin => _isAdmin;

  /// Лимит «по умолчанию для всех» (как настроил админ).
  int get defaultMb => _defaultMb;

  /// Персональные лимиты: Matrix ID → МБ (копия).
  Map<String, int> get users => Map.unmodifiable(_users);

  /// Служебная комната уже создана на сервере.
  bool get hasSettingsRoom => _roomId != null;

  /// Действующий лимит сотрудника в МБ (с учётом потолка сервера).
  int limitMbFor(String userId) =>
      math.min(_users[userId] ?? _defaultMb, _serverCapMb);

  /// Действующий лимит текущего пользователя.
  int get myLimitMb => limitMbFor(_client?.userID ?? '');
  int get myLimitBytes => myLimitMb * _mb;

  /// Служебная комната настроек — её не показываем в списках чатов.
  bool isSettingsRoom(matrix.Room room) {
    if (_roomId != null && room.id == _roomId) return true;
    final alias = room.canonicalAlias;
    return alias.startsWith('#$aliasLocalpart:');
  }

  // ─── Подключение к клиенту ────────────────────────────────────────────────

  /// Вызывается один раз после входа (MatrixService._afterLogin).
  Future<void> attach(matrix.Client client) async {
    if (identical(_client, client)) return;
    _client = client;
    await _syncSub?.cancel();
    _syncSub = client.onSync.stream.listen((_) => _onSync());
    await Future.wait([_loadServerCap(), _checkAdmin(), _resolveRoom()]);
    _readState();
    notifyListeners();
  }

  String get _alias {
    final me = _client?.userID ?? '';
    final i = me.indexOf(':');
    final server = i == -1 ? 'matrix.sgo.kz' : me.substring(i + 1);
    return '#$aliasLocalpart:$server';
  }

  void _onSync() {
    // Комнаты ещё нет (админ не создал) — пробуем найти раз в 10 минут.
    if (_roomId == null) {
      final last = _lastResolve;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 10)) {
        unawaited(
          _resolveRoom().then((_) {
            if (_readState()) notifyListeners();
          }),
        );
      }
      return;
    }
    if (_readState()) notifyListeners();
  }

  // Находит служебную комнату по адресу и вступает в неё (только чтение).
  Future<void> _resolveRoom() async {
    final c = _client;
    if (c == null || _resolving) return;
    _resolving = true;
    _lastResolve = DateTime.now();
    try {
      final resp = await c.getRoomIdByAlias(_alias);
      final id = resp.roomId;
      if (id == null) return;
      _roomId = id;
      final room = c.getRoomById(id);
      if (room == null || room.membership != matrix.Membership.join) {
        await c.joinRoom(id);
      }
    } catch (e) {
      // M_NOT_FOUND — админ ещё не создал комнату. Работаем с 20 МБ.
      debugPrint('UploadLimits: комната настроек не найдена ($e)');
    } finally {
      _resolving = false;
    }
  }

  // Читает настройки из state комнаты. Возвращает true, если что-то поменялось.
  bool _readState() {
    final id = _roomId;
    final c = _client;
    if (id == null || c == null) return false;
    final room = c.getRoomById(id);
    if (room == null) return false;
    final content = room.getState(stateType)?.content;
    if (content == null) return false;

    final d = content['default_mb'];
    final newDefault = d is num ? d.toInt() : defaultLimitMb;
    final newUsers = <String, int>{};
    final u = content['users'];
    if (u is Map) {
      u.forEach((k, v) {
        if (v is num) newUsers[k.toString()] = v.toInt();
      });
    }
    final changed = newDefault != _defaultMb || !mapEquals(newUsers, _users);
    _defaultMb = newDefault;
    _users = newUsers;
    return changed;
  }

  // ─── Запросы к серверу ────────────────────────────────────────────────────

  Map<String, String> _authHeaders() {
    final token = _client?.accessToken;
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }

  // Потолок сервера: m.upload.size из /media/config.
  Future<void> _loadServerCap() async {
    final c = _client;
    final hs = c?.homeserver;
    if (c == null || hs == null) return;
    for (final path in const [
      '/_matrix/client/v1/media/config',
      '/_matrix/media/v3/config',
    ]) {
      try {
        final resp = await c.httpClient.get(
          hs.resolve(path),
          headers: _authHeaders(),
        );
        if (resp.statusCode != 200) continue;
        final size = (jsonDecode(resp.body) as Map)['m.upload.size'];
        if (size is num && size > 0) {
          _serverCapMb = math.max(1, size.toInt() ~/ _mb);
          return;
        }
      } catch (_) {
        // пробуем следующий путь
      }
    }
  }

  // Админ ли я: этот запрос отвечает 200 только администраторам сервера.
  Future<void> _checkAdmin() async {
    final c = _client;
    final hs = c?.homeserver;
    final me = c?.userID;
    if (c == null || hs == null || me == null) return;
    try {
      final resp = await c.httpClient.get(
        hs.resolve('/_synapse/admin/v1/users/${Uri.encodeComponent(me)}/admin'),
        headers: _authHeaders(),
      );
      _isAdmin =
          resp.statusCode == 200 &&
          (jsonDecode(resp.body) as Map)['admin'] == true;
    } catch (_) {
      _isAdmin = false;
    }
  }

  // ─── Действия администратора ──────────────────────────────────────────────

  /// Создаёт служебную комнату, если её ещё нет. Вызывается при открытии
  /// экрана «Лимиты файлов». Сделайте это СРАЗУ после установки новой
  /// версии на свой ПК: пока комнаты нет, адрес может занять кто угодно.
  Future<void> ensureSettingsRoom() async {
    if (!_isAdmin) {
      throw Exception('Нет прав администратора сервера');
    }
    if (_roomId != null) return;
    await _resolveRoom();
    if (_roomId != null) {
      _readState();
      notifyListeners();
      return;
    }
    final c = _client!;
    final me = c.userID!;
    final id = await c.createRoom(
      name: 'ABYROY · Настройки',
      topic: 'Служебная комната. Не удалять.',
      roomAliasName: aliasLocalpart,
      visibility: matrix.Visibility.private,
      // public — вступить может любой сотрудник (только чтение),
      // приглашать 2000 человек не нужно.
      preset: matrix.CreateRoomPreset.publicChat,
      powerLevelContentOverride: {
        'users': {me: 100},
        'users_default': 0,
        'events_default': 100, // писать сообщения — только админ
        'state_default': 100, // менять настройки — только админ
        'invite': 100,
        'kick': 100,
        'ban': 100,
        'redact': 100,
      },
      initialState: [
        matrix.StateEvent(
          type: stateType,
          stateKey: '',
          content: _content(_defaultMb, _users),
        ),
      ],
    );
    _roomId = id;
    notifyListeners();
  }

  /// Сохраняет настройки (только админ).
  Future<void> save({
    required int defaultMb,
    required Map<String, int> users,
  }) async {
    if (!_isAdmin) {
      throw Exception('Нет прав администратора сервера');
    }
    if (_roomId == null) await ensureSettingsRoom();
    final c = _client!;
    await c.setRoomStateWithKey(
      _roomId!,
      stateType,
      '',
      _content(defaultMb, users),
    );
    _defaultMb = defaultMb;
    _users = Map.of(users);
    notifyListeners();
  }

  Map<String, Object?> _content(int defaultMb, Map<String, int> users) => {
    'default_mb': defaultMb,
    'users': users,
    'updated_by': _client?.userID,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };
}
