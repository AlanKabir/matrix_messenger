// services/notification_sound.dart — звук входящего сообщения.
// Проигрывает стандартный системный звук уведомления Windows напрямую
// через user32.dll (MessageBeep) — без дополнительных пакетов.
//
// ПОДКЛЮЧЕНИЕ (одна строка в desktop_service.dart):
//   1) вверху добавить импорт:
//        import 'notification_sound.dart';
//   2) там, где показывается уведомление (вызов ...show() у
//      LocalNotification), строкой выше добавить:
//        NotificationSound.play();

import 'dart:ffi';
import 'dart:io';

class NotificationSound {
  NotificationSound._();

  static DynamicLibrary? _user32;
  static int Function(int)? _beep;

  // Не звенеть чаще, чем раз в 2 секунды: при пачке сообщений
  // (вход в группу, догоняющая синхронизация) сплошной звон раздражает.
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static void play() {
    if (!Platform.isWindows) return;
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(seconds: 2)) return;
    _last = now;
    try {
      _user32 ??= DynamicLibrary.open('user32.dll');
      _beep ??= _user32!
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'MessageBeep',
          );
      // 0x40 = MB_ICONASTERISK — стандартный «звук уведомления» из схемы
      // звуков Windows (тот же, что у системных подсказок).
      _beep!(0x40);
    } catch (_) {
      // Нет звука — не критично, уведомление всё равно показано.
    }
  }
}
