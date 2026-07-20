// services/sso_login.dart — бесшовный вход через Synapse SSO (Keycloak/Kerberos).

import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class SsoException implements Exception {
  final String message;
  SsoException(this.message);
  @override
  String toString() => message;
}

class SsoLogin {
  final String homeserver; // например http://matrix.sgo.kz:8008

  SsoLogin(this.homeserver);

  /// Возвращает loginToken для client.login(mLoginToken).
  Future<String> acquireLoginToken({
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<String>();

    server.listen((HttpRequest req) async {
      final token = req.uri.queryParameters['loginToken'];
      req.response.headers.contentType = ContentType.html;
      req.response.write(_resultPage(ok: token != null));
      await req.response.close();
      if (token != null && !completer.isCompleted) {
        completer.complete(token);
      }
    });

    final redirect = 'http://127.0.0.1:${server.port}/callback';
    // idp_id из oidc_providers в homeserver.yaml (у вас — keycloak).
    const idpId = 'oidc-keycloak';
    final idpPath = idpId.isEmpty ? '' : '/$idpId';
    final url = Uri.parse(
      '$homeserver/_matrix/client/v3/login/sso/redirect$idpPath'
      '?redirectUrl=${Uri.encodeComponent(redirect)}',
    );

    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched) {
      await server.close(force: true);
      throw SsoException('Не удалось открыть браузер для входа');
    }

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw SsoException('Время ожидания входа истекло'),
      );
    } finally {
      await server.close(force: true);
    }
  }

  String _resultPage({required bool ok}) =>
      '''
<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8">
<title>Корпоративный мессенджер</title>
<style>
 body{font-family:"Segoe UI",sans-serif;background:#F0F2F5;display:flex;
      align-items:center;justify-content:center;height:100vh;margin:0}
 .card{background:#fff;border-radius:12px;padding:40px 56px;text-align:center;
       box-shadow:0 2px 12px rgba(0,0,0,.1)}
 h2{color:${ok ? '#128C7E' : '#C62828'};margin:0 0 8px}
 p{color:#667781;margin:0}
</style></head><body><div class="card">
<h2>${ok ? 'Вход выполнен' : 'Ошибка входа'}</h2>
<p>${ok ? 'Вернитесь в приложение. Это окно можно закрыть.' : 'Закройте окно и повторите попытку в приложении.'}</p>
</div><script>setTimeout(()=>window.close(),1500)</script></body></html>''';
}
