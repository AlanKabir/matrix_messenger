import 'package:flutter/material.dart';

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
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent, // Основной неоново-зеленый акцент
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// Изменился тип виджета: теперь он поддерживает состояние (Stateful)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Контроллеры — это программные "щупальца", считывающие текст из полей
  final TextEditingController _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    // Очищаем память контроллеров при закрытии экрана
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    // Функция запускается по клику на кнопку. Пока что выводим данные в консоль VS Code
    print('=== ПОПЫТКА АВТОРИЗАЦИИ MATRIX ===');
    print('Сервер: ${_homeserverController.text}');
    print('Логин: ${_usernameController.text}');
    print('Пароль: ${_passwordController.text}');
    print('==================================');
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
            constraints: const BoxConstraints(
              maxWidth: 400,
            ), // Ограничение ширины для аккуратного вида на ПК
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 72, color: Colors.greenAccent),
                const SizedBox(height: 32),
                TextField(
                  controller: _homeserverController,
                  decoration: const InputDecoration(
                    labelText: 'Домашний сервер Matrix',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя (напр. @neo:matrix.org)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true, // Скрывает вводимый пароль звездочками
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _login,
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
                  child: const Text('ПОДКЛЮЧИТЬСЯ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
