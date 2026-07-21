import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';
import 'services/desktop_service.dart';
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

  // --- окно, трей, уведомления (Windows) ---
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1100, 720),
      minimumSize: Size(800, 560),
      center: true,
      title: 'Мессенджер SGO',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await localNotifier.setup(appName: 'Мессенджер SGO');
  await DesktopService.instance.init();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Мессенджер SGO',
      theme: T.theme(),
      home: const LoginScreen(),
    ),
  );
}
