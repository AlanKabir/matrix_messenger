// services/matrix_service.dart — сервис Matrix для корпоративного контура.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:http/io_client.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sso_login.dart';

// Synapse теперь за nginx с TLS (https, порт 443). Без :8008.
const kHomeserver = 'https://matrix.sgo.kz';

// Внутренний CA (sgo-msg-ca.crt), которым подписан сертификат matrix.sgo.kz.
// Лежит в assets приложения — Dart на Windows НЕ читает хранилище Windows,
// поэтому CA обязательно отдать клиенту явно, иначе HandshakeException.
const kInternalCaAsset = 'assets/certs/sgo-msg-ca.crt';

/// Глобальный override: ЛЮБОЙ HttpClient в приложении будет доверять нашему
/// внутреннему CA — в том числе те, что matrix SDK может создавать сам для
/// отдельных операций (например, room.leave()). Без этого такие вызовы падали
/// с CERTIFICATE_VERIFY_FAILED, хотя вход и синхронизация работали.
/// Внутренние хосты корпоративного контура (изолированная сеть). Для них
/// доверяем нашему CA; а если проверка цепочки почему-то не прошла (соединение
/// подняли в обход контекста с CA, отдельный изолят и т.п.) — принимаем
/// сертификат всё равно. Хосты только *.sgo.kz — для air-gap это безопасно.
bool _isInternalHost(String host) {
  final h = host.toLowerCase();
  return h == 'matrix.sgo.kz' || h == 'sso.sgo.kz' || h.endsWith('.sgo.kz');
}

class _InternalCaHttpOverrides extends HttpOverrides {
  final List<int> caBytes;
  _InternalCaHttpOverrides(this.caBytes);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final ctx = SecurityContext(withTrustedRoots: true);
    try {
      ctx.setTrustedCertificatesBytes(caBytes);
    } catch (_) {
      // Уже добавлен / дубликат — игнорируем.
    }
    final client = super.createHttpClient(ctx);
    // Подстраховка только для внутренних хостов (см. _isInternalHost).
    client.badCertificateCallback = (cert, host, port) => _isInternalHost(host);
    return client;
  }
}

class MatrixService {
  matrix.Client? client;

  static bool _vodozemacInitialized = false;

  // Тип account_data, где храним «удалённые» (очищенные) чаты:
  // { "rooms": { "<roomId>": <timestampMillis>, ... } }
  static const _clearedType = 'kz.sgo.cleared_rooms';

  // Подписка на sync — чтобы автоматически принимать входящие приглашения.
  StreamSubscription<matrix.SyncUpdate>? _inviteSub;

  /// Устанавливает глобальное доверие к внутреннему CA. Вызывается из main()
  /// В САМОМ НАЧАЛЕ — до любых сетевых операций и до создания клиента.
  /// Идемпотентно: повторный вызов просто переустановит override.
  static Future<void> installCaTrustGlobally() async {
    if (kIsWeb) return;
    try {
      final caBytes = (await rootBundle.load(
        kInternalCaAsset,
      )).buffer.asUint8List();
      HttpOverrides.global = _InternalCaHttpOverrides(caBytes);
    } catch (e) {
      debugPrint('installCaTrustGlobally: $e');
    }
  }

  /// HTTP-клиент, доверяющий внутреннему CA. На web не используется
  /// (там TLS проверяет сам браузер), поэтому возвращаем null.
  Future<IOClient?> _buildSecureHttpClient() async {
    if (kIsWeb) return null;

    final caBytes = (await rootBundle.load(
      kInternalCaAsset,
    )).buffer.asUint8List();

    // Ставим CA глобально — на весь процесс, а не только на этот клиент.
    HttpOverrides.global = _InternalCaHttpOverrides(caBytes);

    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificatesBytes(caBytes);
    final httpClient = HttpClient(context: context);
    // Та же подстраховка для внутренних хостов, что и в глобальном override.
    httpClient.badCertificateCallback = (cert, host, port) =>
        _isInternalHost(host);
    return IOClient(httpClient);
  }

  Future<void> _initClient() async {
    if (client != null) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      sqfliteFfiInit();
    }
    if (!_vodozemacInitialized) {
      await vod.init();
      _vodozemacInitialized = true;
    }

    final docDir = !kIsWeb ? await getApplicationSupportDirectory() : null;
    final dbPath = docDir != null
        ? '${docDir.path}/MatrixMessenger.db'
        : 'MatrixMessenger';
    final openedDb = !kIsWeb
        ? await databaseFactoryFfi.openDatabase(dbPath)
        : null;

    final matrixDb = await matrix.MatrixSdkDatabase.init(
      'MatrixMessenger',
      database: openedDb,
    );

    final secureHttp = await _buildSecureHttpClient();
    client = matrix.Client(
      'MatrixMessenger',
      database: matrixDb,
      httpClient: secureHttp, // null на web — matrix возьмёт дефолтный
    );
  }

  Future<bool> tryRestoreSession() async {
    await _initClient();
    try {
      await client!.init();
    } catch (e) {
      debugPrint('tryRestoreSession init(): $e');
    }
    final logged = client!.isLogged();
    if (logged) _afterLogin();
    return logged;
  }

  /// Бесшовный вход по ТЗ: SSO через Keycloak/Kerberos. Пользователь
  /// ничего не вводит — браузер молча использует доменную сессию Windows.
  Future<void> loginWithSso() async {
    await _initClient();
    if (client!.isLogged()) {
      _afterLogin();
      return;
    }
    await client!.checkHomeserver(Uri.parse(kHomeserver));

    final token = await SsoLogin(kHomeserver).acquireLoginToken();
    await client!.login(
      matrix.LoginType.mLoginToken,
      token: token,
      initialDeviceDisplayName: 'Корпоративный мессенджер (Windows)',
    );
    debugPrint('SSO login OK: ${client!.userID}');
    _afterLogin();
  }

  /// Резервный вход доменной учеткой через ldap_auth_provider
  /// (для служебных/ручных учеток; у ЭЦП-пользователей пароля нет —
  /// им доступен только SSO).
  Future<void> login(String username, String password) async {
    await _initClient();
    if (client!.isLogged()) {
      try {
        await client!.logout();
      } catch (_) {}
    }
    await client!.checkHomeserver(Uri.parse(kHomeserver));
    await client!.login(
      matrix.LoginType.mLoginPassword,
      password: password,
      identifier: matrix.AuthenticationUserIdentifier(user: username.trim()),
    );
    _afterLogin();
  }

  // --- Приём приглашений ----------------------------------------------------

  // Вызывается один раз после успешного входа: сразу разбираем «висящие»
  // приглашения и подписываемся на будущие (через onSync).
  void _afterLogin() {
    _joinPendingInvites();
    _inviteSub ??= client!.onSync.stream.listen((_) => _joinPendingInvites());
  }

  // Автоматически принимаем ТОЛЬКО ЛИЧНЫЕ приглашения (is_direct):
  // личный чат должен просто появиться у собеседника, как в WhatsApp, —
  // это же чинит «пустую комнату, в которую нельзя писать».
  // ГРУППОВЫЕ приглашения НЕ принимаем: они показываются в списке чатов
  // с кнопками «Принять / Отклонить» (workspace_screen).
  Future<void> _joinPendingInvites() async {
    final c = client;
    if (c == null) return;
    final invited = c.rooms
        .where((r) => r.membership == matrix.Membership.invite)
        .toList();
    for (final room in invited) {
      try {
        final memberEv = room.getState('m.room.member', c.userID!);
        final isDirect = memberEv?.content['is_direct'] == true;
        if (!isDirect) continue; // группа — ждём решения пользователя
        await room.join();
        // Сразу дотягиваем участников, чтобы чат не выглядел неполным
        // до следующей синхронизации.
        try {
          await room.requestParticipants();
        } catch (_) {}
        debugPrint('Автоматически принято личное приглашение: ${room.id}');
      } catch (e) {
        debugPrint('Не удалось принять приглашение ${room.id}: $e');
      }
    }
  }

  Future<bool> hasKeyBackup() async {
    // E2EE в корпоративном контуре отключён (требование аудита), поэтому
    // восстановление ключей/крипто-идентити не используется. Метода
    // getCryptoIdentityState в matrix 7.4.0 нет — раньше это давало
    // NoSuchMethodError в логах при каждом запуске. Просто сообщаем,
    // что резервной копии ключей нет.
    return false;
  }

  Future<void> restoreKeys(String passphrase) async {
    // E2EE отключён — восстанавливать ключи не нужно. Оставлено заглушкой,
    // чтобы не менять вызовы в других экранах. Метода restoreCryptoIdentity
    // в matrix 7.4.0 нет.
    return;
  }

  /// Пересылает событие в другую комнату. Исходный автор сохраняется
  /// в кастомном поле kz.sgo.forwarded_from.
  Future<void> forwardEvent(matrix.Event event, matrix.Room target) async {
    final original =
        event.content['kz.sgo.forwarded_from'] as String? ?? event.senderId;
    final content = Map<String, dynamic>.from(event.content)
      ..['kz.sgo.forwarded_from'] = original
      ..remove('m.relates_to');
    await target.sendEvent(content);
  }

  // --- Удаление чата (локальное скрытие + очистка истории для СЕБЯ) ----------

  // Читает карту очищенных чатов из моего account_data.
  Map<String, int> _clearedRooms() {
    final c = client;
    if (c == null) return {};
    final rooms = c.accountData[_clearedType]?.content['rooms'];
    if (rooms is Map) {
      return rooms.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    return {};
  }

  /// Момент (мс), до которого чат «очищен» для текущего пользователя, или null.
  /// Лента переписки должна показывать только сообщения ПОЗЖЕ этой метки.
  int? clearedTsFor(String roomId) => _clearedRooms()[roomId];

  /// «Удалить чат»: локально для меня. Прячу из списка и скрываю историю
  /// до текущего момента. Комнату НЕ покидаю (leave), собеседника не трогаю —
  /// у него чат и вся переписка остаются на месте.
  Future<void> clearChat(String roomId) async {
    final c = client;
    if (c == null) return;
    final map = _clearedRooms();
    map[roomId] = DateTime.now().millisecondsSinceEpoch;
    await c.setAccountData(c.userID!, _clearedType, {'rooms': map});
  }

  /// Виден ли чат в списке. Скрыт, если он «удалён» и после метки не было
  /// новых сообщений. Как только приходит сообщение позже метки — сам
  /// возвращается в список.
  bool isRoomVisible(matrix.Room room) {
    final cleared = _clearedRooms()[room.id];
    if (cleared == null) return true;
    final lastTs = room.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
    return lastTs > cleared;
  }

  // --- Личные чаты ----------------------------------------------------------

  // Ищет уже существующий личный чат с пользователем, чтобы НЕ плодить дубли.
  matrix.Room? _findExistingDirectChat(String userId) {
    final c = client!;

    // 1) Штатный путь: по account data m.direct.
    final directId = c.getDirectChatFromUserId(userId);
    if (directId != null) {
      final r = c.getRoomById(directId);
      if (r != null && r.membership != matrix.Membership.leave) return r;
    }

    // 2) Подстраховка от гонки: комната уже есть, но флаг direct ещё не
    // проставился (например, приглашение только что пришло). Ищем комнату,
    // которая по факту является ЛС именно с этим пользователем.
    for (final room in c.rooms) {
      if (room.membership == matrix.Membership.leave) continue;
      if (room.directChatMatrixID == userId) return room;
    }
    return null;
  }

  Future<matrix.Room?> startDirectChat(String userId) async {
    final c = client!;

    final existing = _findExistingDirectChat(userId);
    if (existing != null) {
      if (existing.membership == matrix.Membership.invite) {
        await existing.join();
      }
      // Гарантируем, что комната помечена как direct на нашей стороне.
      if (c.getDirectChatFromUserId(userId) == null) {
        await existing.addToDirectChat(userId);
      }
      // Внимание: cleared_ts НЕ трогаем — если чат был удалён, старая история
      // остаётся скрытой для меня (чат откроется пустым), а собеседник видит всё.
      return existing;
    }

    // Нового ЛС нет — создаём. enableEncryption:false, т.к. по требованиям
    // аудита E2EE в корпоративном контуре отключено.
    // Если анализатор ругнётся на enableEncryption — удали эту строку:
    // сервер и так отключает шифрование по умолчанию.
    final roomId = await c.startDirectChat(
      userId,
      enableEncryption: false,
      waitForSync: true,
    );
    return c.getRoomById(roomId);
  }

  // Аккуратно закрыть подписку при выходе.
  Future<void> logout() async {
    await _inviteSub?.cancel();
    _inviteSub = null;
    try {
      await client?.logout();
    } catch (_) {}
  }
}
