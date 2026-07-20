import 'dart:io';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logs().level = Level.verbose;

  // Пишем все логи в файл рядом с данными приложения.
  final dir = await getApplicationSupportDirectory();
  final logFile = File('${dir.path}/messenger_log.txt');
  await logFile.writeAsString(
    '=== Запуск ${DateTime.now()} ===\n',
    mode: FileMode.append,
  );
  final origDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      logFile.writeAsStringSync('$message\n', mode: FileMode.append);
    }
    origDebugPrint(message, wrapWidth: wrapWidth);
  };

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Мессенджер SGO',
      theme: T.theme(),
      home: const LoginScreen(),
    ),
  );
}
