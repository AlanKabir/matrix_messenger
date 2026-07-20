// screens/login_screen.dart — вход по ТЗ: БЕЗ полей логина и пароля.
//
// Порядок при запуске:
//  1. Пытаемся восстановить сохраненную сессию (как у вас было).
//  2. Если сессии нет — проверяем, что машина в домене, и АВТОМАТИЧЕСКИ
//     запускаем SSO-флоу (браузер → Keycloak → Kerberos → loginToken).
//  3. Успех → восстановление E2EE-ключей (ваш диалог Security Phrase) →
//     рабочее окно. Ошибка → экран с кнопкой «Повторить вход».
//
// Скрытый служебный вход по паролю (LDAP) оставлен за маленькой ссылкой
// внизу — для админов и ручных учеток. Не нужен — удалите _PasswordFallback.

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/matrix_service.dart';
import '../widgets/common.dart';
import 'workspace_screen.dart';

const kFatalMessage =
    'Ошибка доступа: Требуется авторизация в корпоративном домене';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Stage { restoring, ssoInProgress, error, passwordFallback }

class _LoginScreenState extends State<LoginScreen> {
  final _matrixService = MatrixService();
  _Stage _stage = _Stage.restoring;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  bool _machineInDomain() {
    // Быстрый pre-check: у машины вне домена нет USERDNSDOMAIN.
    // Настоящая защита — на сервере: без Kerberos-тикета Keycloak не пустит.
    return (Platform.environment['USERDNSDOMAIN'] ?? '').isNotEmpty;
  }

  Future<void> _bootstrap() async {
    bool restored = false;
    try {
      restored = await _matrixService.tryRestoreSession();
    } catch (_) {}
    if (!mounted) return;

    if (restored) {
      await _finishLogin();
      return;
    }
    if (!_machineInDomain()) {
      setState(() {
        _stage = _Stage.error;
        _errorText = kFatalMessage;
      });
      return;
    }
    await _startSso();
  }

  Future<void> _startSso() async {
    setState(() => _stage = _Stage.ssoInProgress);
    try {
      await _matrixService.loginWithSso();
      if (mounted) await _finishLogin();
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorText = 'Не удалось выполнить вход через SSO.\n$e';
        });
      }
    }
  }

  Future<void> _finishLogin() async {
    await _checkAndRestoreKeys();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => WorkspaceScreen(matrixService: _matrixService)));
  }

  // ------ ваш диалог Security Phrase, без изменений ------
  Future<void> _checkAndRestoreKeys() async {
    final needsBackup = await _matrixService.hasKeyBackup();
    if (!mounted || !needsBackup) return;

    final phrase = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Ключ расшифровки истории'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Введите Security Phrase, чтобы расшифровать историю '
                'сообщений на этом устройстве:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                decoration:
                    const InputDecoration(hintText: 'Секретная фраза'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text),
              child: const Text('Расшифровать'),
            ),
          ],
        );
      },
    );
    if (phrase != null && phrase.isNotEmpty) {
      await _matrixService.restoreKeys(phrase);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.restoring:
        return const _Progress('Запуск приложения...');
      case _Stage.ssoInProgress:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const _Progress('Выполняется вход через корпоративный SSO...'),
          const SizedBox(height: 8),
          const Text('В браузере откроется страница входа —\n'
              'она закроется автоматически.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12.5)),
          const SizedBox(height: 20),
          TextButton(
              onPressed: _startSso, child: const Text('Открыть еще раз')),
        ]);
      case _Stage.error:
        final isDomainError = _errorText == kFatalMessage;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(isDomainError ? Icons.gpp_bad_outlined : Icons.error_outline,
              size: 80, color: Colors.red),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(_errorText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(height: 8),
          const Text('Обратитесь к системному администратору.',
              style: TextStyle(color: Colors.black45, fontSize: 12.5)),
          const SizedBox(height: 24),
          if (!isDomainError)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              onPressed: _startSso,
              child: const Text('Повторить вход'),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () =>
                setState(() => _stage = _Stage.passwordFallback),
            child: const Text('Служебный вход по паролю',
                style: TextStyle(fontSize: 12, color: Colors.black38)),
          ),
        ]);
      case _Stage.passwordFallback:
        return _PasswordFallback(
          service: _matrixService,
          onSuccess: _finishLogin,
          onBack: () => setState(() => _stage = _Stage.error),
        );
    }
  }
}

class _Progress extends StatelessWidget {
  final String text;
  const _Progress(this.text);

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: kAccent),
        const SizedBox(height: 16),
        Text(text, style: const TextStyle(color: Colors.black54)),
      ]);
}

/// Служебный вход по паролю (LDAP) — для админов и ручных учеток.
class _PasswordFallback extends StatefulWidget {
  final MatrixService service;
  final Future<void> Function() onSuccess;
  final VoidCallback onBack;
  const _PasswordFallback(
      {required this.service, required this.onSuccess, required this.onBack});

  @override
  State<_PasswordFallback> createState() => _PasswordFallbackState();
}

class _PasswordFallbackState extends State<_PasswordFallback> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.service.login(_user.text, _pass.text);
      await widget.onSuccess();
    } catch (e) {
      setState(() => _error = 'Ошибка входа: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Служебный вход',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
                controller: _user,
                decoration: const InputDecoration(
                    labelText: 'Учетная запись',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _pass,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                    labelText: 'Пароль', border: OutlineInputBorder())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            Row(children: [
              TextButton(
                  onPressed: widget.onBack, child: const Text('Назад')),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kAccent),
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Войти'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
