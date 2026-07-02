// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import '../services/matrix_service.dart';
import 'workspace_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _matrixService = MatrixService();

  bool _isLoading = false;
  bool _isCheckingSession = true; // Защита от преждевременного клика

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  void _openSecureTerminal() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            WorkspaceScreen(matrixService: _matrixService),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _checkAutoLogin() async {
    bool isLoggedIn = false;
    try {
      isLoggedIn = await _matrixService.tryRestoreSession();
    } catch (_) {}

    if (!mounted) return;

    if (isLoggedIn) {
      print("⚡ Авто-вход выполнен! Проверяем ключи...");
      await _checkAndRestoreKeys();
      if (mounted) _openSecureTerminal();
    } else {
      // Сессии нет (или она была багованной) — показываем поля ввода
      setState(() {
        _isCheckingSession = false;
      });
    }
  }

  Future<void> _checkAndRestoreKeys() async {
    bool needsBackup = await _matrixService.hasKeyBackup();
    if (!mounted) return;

    if (needsBackup) {
      final phrase = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final controller = TextEditingController();
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Ключ дешифровки',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Введите Security Phrase для расшифровки истории сообщений:',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Ваша секретная фраза...',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.greenAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text(
                  'РАСШИФРОВАТЬ',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (phrase != null && phrase.isNotEmpty) {
        await _matrixService.restoreKeys(phrase);
      }
    }
  }

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Введите логин и пароль')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _matrixService.login(
        _homeserverController.text,
        _usernameController.text,
        _passwordController.text,
      );

      await _checkAndRestoreKeys();

      if (mounted) _openSecureTerminal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('❌ Ошибка: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('MATRIX // Терминал доступа'),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: _isCheckingSession
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 16),
                  Text(
                    'Инициализация крипто-хранилища...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.security,
                        size: 72,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _homeserverController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Сервер',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Логин',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Пароль',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'ПОДКЛЮЧИТЬСЯ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
