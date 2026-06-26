import 'package:flutter/material.dart';

void main() {
  runApp(const MatrixMessengerApp());
}

class MatrixMessengerApp extends StatelessWidget {
  const MatrixMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          false, // Убирает красную ленточку "DEBUG" в углу
      title: 'Matrix Messenger',
      theme: ThemeData.dark(), // Включаем темную хакерскую тему
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Глубокий темный фон
      appBar: AppBar(
        title: const Text(
          'MATRIX // Вход в сеть',
          style: TextStyle(letterSpacing: 2),
        ),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: const Center(
        child: Text(
          'Система готова к авторизации...',
          style: TextStyle(
            color: Colors.greenAccent, // Неоновый зеленый цвет Matrix
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
