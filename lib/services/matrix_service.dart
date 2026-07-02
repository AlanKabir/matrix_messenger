import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/encryption.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MatrixService {
  matrix.Client? client;

  // Глобальный флаг — общий для ВСЕХ экземпляров MatrixService
  static bool _vodozemacInitialized = false;

  Future<void> _initClient() async {
    if (client != null) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      sqfliteFfiInit();
    }

    // Инициализируем vodozemac только один раз за всё время работы приложения
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
    client = matrix.Client('MatrixMessenger', database: matrixDb);
  }

  Future<bool> tryRestoreSession() async {
    await _initClient();
    debugPrint(
      "🔍 [tryRestoreSession] До init(): isLogged=${client!.isLogged()}",
    );
    try {
      await client!.init();
    } catch (e) {
      debugPrint("⚠️ [tryRestoreSession] Исключение в init(): $e");
    }
    final result = client!.isLogged();
    debugPrint(
      "🔍 [tryRestoreSession] После init(): isLogged=$result, userID=${client!.userID}, deviceID=${client!.deviceID}",
    );
    return result;
  }

  Future<void> login(
    String homeserverUrl,
    String username,
    String password,
  ) async {
    await _initClient();

    if (client!.isLogged()) {
      debugPrint("⚡ Клиент уже залогинен, выполняем logout()");
      try {
        await client!.logout();
      } catch (e) {
        debugPrint("⚠️ Logout завершился с ошибкой: $e");
      }
    }

    final homeserverUri = Uri.parse(homeserverUrl);
    await client!.checkHomeserver(homeserverUri);

    await client!.login(
      matrix.LoginType.mLoginPassword,
      password: password,
      identifier: matrix.AuthenticationUserIdentifier(user: username.trim()),
    );

    debugPrint("✅ [login] Вход выполнен, клиент готов к работе");
    // client!.init() больше не нужен — login() уже сам всё инициализировал
  }

  Future<bool> hasKeyBackup() async {
    if (client == null || client!.encryption == null) return false;
    try {
      final state = await client!.getCryptoIdentityState();
      // initialized = identity была настроена раньше,
      // connected = уже подключена на этом устройстве
      return state.initialized && !state.connected;
    } catch (e) {
      debugPrint("Не удалось получить состояние крипто-идентичности: $e");
      return false;
    }
  }

  Future<void> restoreKeys(String passphrase) async {
    if (client == null || client!.encryption == null) return;
    try {
      await client!.restoreCryptoIdentity(passphrase);
      debugPrint("⚡ Крипто-идентичность успешно восстановлена!");
    } catch (e) {
      debugPrint("❌ Не удалось восстановить ключи: $e");
      rethrow;
    }
  }
}
