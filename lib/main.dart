// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  runApp(const MatrixMessengerApp());
}

class MatrixMessengerApp extends StatelessWidget {
  const MatrixMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Matrix Messenger',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(primary: Colors.greenAccent),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Введите логин и пароль')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // НАША ДОБЫЧА ИЗ РАЗВЕДКИ: Передаем клиенту родной MatrixSdkDatabase!
      final client = matrix.Client(
        'MatrixMessenger',
        database: await matrix.MatrixSdkDatabase.init('MatrixMessenger'),
      );

      final homeserverUri = Uri.parse(_homeserverController.text.trim());
      await client.checkHomeserver(homeserverUri);

      await client.login(
        matrix.LoginType.mLoginPassword,
        password: _passwordController.text,
        identifier: matrix.AuthenticationUserIdentifier(
          user: _usernameController.text.trim(),
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ ДОСТУП РАЗРЕШЕН! Успешный вход в Matrix.'),
          ),
        );
      }
    } catch (e) {
      print('Ошибка авторизации Matrix: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              '❌ ОТКАЗАНО В ДОСТУПЕ: Неверный пароль или пользователь не найден.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MATRIX // Терминал доступа',
          style: TextStyle(letterSpacing: 2),
        ),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 72, color: Colors.greenAccent),
                const SizedBox(height: 32),
                TextField(
                  controller: _homeserverController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Домашний сервер Matrix',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('ПОДКЛЮЧИТЬСЯ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
