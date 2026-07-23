// services/autostart_service.dart — автозапуск мессенджера при входе в Windows.
// Использует пакет launch_at_startup: запись в реестр
// HKCU\Software\Microsoft\Windows\CurrentVersion\Run (права админа НЕ нужны,
// работает для текущего пользователя — как раз наш случай с доменными ПК).
//
// Подключение в main.dart (после ensureInitialized, до runApp):
//   await AutostartService.instance.init();
//
// В настройках:
//   value: AutostartService.instance.enabled
//   onChanged: (v) => AutostartService.instance.setEnabled(v)

import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

class AutostartService {
  AutostartService._();
  static final AutostartService instance = AutostartService._();

  bool _enabled = false;
  bool _ready = false;

  bool get enabled => _enabled;

  // Вызывать один раз при старте приложения.
  Future<void> init() async {
    if (!Platform.isWindows) return;
    try {
      launchAtStartup.setup(
        appName: 'Мессенджер SGO',
        appPath: Platform.resolvedExecutable,
      );
      _enabled = await launchAtStartup.isEnabled();
      _ready = true;
    } catch (_) {
      // Реестр недоступен (сильно урезанные права) — просто живём без
      // автозапуска, приложение работает как раньше.
      _ready = false;
    }
  }

  // Включить/выключить автозапуск. Возвращает итоговое состояние.
  Future<bool> setEnabled(bool value) async {
    if (!_ready) return _enabled;
    try {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      _enabled = await launchAtStartup.isEnabled();
    } catch (_) {}
    return _enabled;
  }
}
