// services/matrix_service.dart — сервис Matrix для корпоративного контура.

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

class MatrixService {
  matrix.Client? client;

  static bool _vodozemacInitialized = false;

  /// HTTP-клиент, доверяющий внутреннему CA. На web не используется
  /// (там TLS проверяет сам браузер), поэтому возвращаем null.
  Future<IOClient?> _buildSecureHttpClient() async {
    if (kIsWeb) return null;
    final context = SecurityContext(withTrustedRoots: true);
    final caBytes = (await rootBundle.load(
      kInternalCaAsset,
    )).buffer.asUint8List();
    context.setTrustedCertificatesBytes(caBytes);
    final httpClient = HttpClient(context: context);
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
    return client!.isLogged();
  }

  /// Бесшовный вход по ТЗ: SSO через Keycloak/Kerberos. Пользователь
  /// ничего не вводит — браузер молча использует доменную сессию Windows.
  Future<void> loginWithSso() async {
    await _initClient();
    if (client!.isLogged()) return;
    await client!.checkHomeserver(Uri.parse(kHomeserver));

    final token = await SsoLogin(kHomeserver).acquireLoginToken();
    await client!.login(
      matrix.LoginType.mLoginToken,
      token: token,
      initialDeviceDisplayName: 'Корпоративный мессенджер (Windows)',
    );
    debugPrint('SSO login OK: ${client!.userID}');
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
  }

  Future<bool> hasKeyBackup() async {
    if (client == null || client!.encryption == null) return false;
    try {
      // API восстановления ключей отличается между версиями matrix SDK.
      // Через dynamic — не ломает сборку на 7.4.0; если метода нет,
      // уходит в catch и вход продолжается без восстановления истории.
      final dynamic c = client;
      final state = await c.getCryptoIdentityState();
      return (state.initialized == true) && (state.connected != true);
    } catch (e) {
      debugPrint('crypto identity state: $e');
      return false;
    }
  }

  Future<void> restoreKeys(String passphrase) async {
    if (client == null || client!.encryption == null) return;
    try {
      final dynamic c = client;
      await c.restoreCryptoIdentity(passphrase);
    } catch (e) {
      debugPrint('restoreKeys: $e');
    }
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

  Future<matrix.Room?> startDirectChat(String userId) async {
    final roomId = await client!.startDirectChat(userId);
    return client!.getRoomById(roomId);
  }
}
