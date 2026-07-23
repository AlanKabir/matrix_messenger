import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'app_theme.dart';
import 'services/autostart_service.dart';
import 'services/desktop_service.dart';
import 'services/matrix_service.dart';
import 'screens/login_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ЗАЩИТА ОТ ВТОРОГО ЭКЗЕМПЛЯРА.
  // Если приложение уже запущено (в том числе спрятано в трее) — новый
  // процесс не стартует, а работающему приходит сигнал: показать окно.
  await WindowsSingleInstance.ensureSingleInstance(
    args,
    'sgo_messenger_single_instance',
    onSecondWindow: (args) async {
      // Сюда попадает ПЕРВЫЙ (работающий) экземпляр, когда пользователь
      // пытается запустить второй. Поднимаем окно из трея.
      await windowManager.show();
      await windowManager.focus();
    },
  );

  Logs().level = Level.verbose;

  // Доверие к внутреннему CA — САМОЕ ПЕРВОЕ сетевое действие, до любых
  // запросов и до создания клиента. Иначе часть операций (поиск людей,
  // удаление чата, отправка файлов) может падать с CERTIFICATE_VERIFY_FAILED.
  await MatrixService.installCaTrustGlobally();

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
  await localNotifier.setup(appName: 'Abyroy Chat');
  await DesktopService.instance.init();

  // Автозапуск при входе в Windows: читаем текущее состояние из реестра,
  // чтобы галочка в настройках показывала правду.
  await AutostartService.instance.init();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Мессенджер SGO',
      theme: T.theme(),
      home: const LoginScreen(),
    ),
  );
}
