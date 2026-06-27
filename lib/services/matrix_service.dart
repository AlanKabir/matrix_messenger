import 'package:matrix/matrix.dart' as matrix;

class MatrixService {
  matrix.Client? client;

  Future<void> _initClient() async {
    // Применили совет линтера: оператор ??= создаст клиента строго один раз
    client ??= matrix.Client(
      'MatrixMessenger',
      database: await matrix.MatrixSdkDatabase.init('MatrixMessenger'),
    );
  }

  Future<bool> tryRestoreSession() async {
    await _initClient();
    await client!.init();
    return client!.isLogged(); // Добавили победные скобки () !
  }

  Future<void> login(
    String homeserverUrl,
    String username,
    String password,
  ) async {
    await _initClient();

    final homeserverUri = Uri.parse(homeserverUrl);
    await client!.checkHomeserver(homeserverUri);

    await client!.login(
      matrix.LoginType.mLoginPassword,
      password: password,
      identifier: matrix.AuthenticationUserIdentifier(user: username.trim()),
    );
  }
}
