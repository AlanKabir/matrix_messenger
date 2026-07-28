// services/desktop_service.dart — трей, уведомления, поведение окна.
// Крестик прячет окно в трей; выход — только через меню трея.
// Новые сообщения показываются системным уведомлением СО ЗВУКОМ,
// когда окно скрыто или не в фокусе.

import 'dart:async';

import 'package:local_notifier/local_notifier.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'notification_sound.dart';

class DesktopService with WindowListener, TrayListener {
  DesktopService._();
  static final DesktopService instance = DesktopService._();

  bool _initialized = false;
  matrix.Client? _client;
  StreamSubscription<matrix.Event>? _eventSub;

  // Иконка трея (положить .ico в assets/ и прописать в pubspec).
  static const _trayIcon = 'assets/tray_icon.ico';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Крестик не закрывает приложение — перехватываем и прячем окно.
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    // Иконка в трее + контекстное меню.
    try {
      await trayManager.setIcon(_trayIcon);
      await trayManager.setToolTip('ABYROY Chat');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Открыть'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Выход'),
          ],
        ),
      );
      trayManager.addListener(this);
    } catch (e) {
      // Если иконка трея не найдена — не роняем приложение.
      // ignore: avoid_print
      print('tray init: $e');
    }
  }

  /// Подключить клиента после входа — начать слушать новые сообщения.
  void attachClient(matrix.Client client) {
    if (_client == client) return;
    _client = client;
    _eventSub?.cancel();
    _eventSub = client.onTimelineEvent.stream.listen(_onEvent);
  }

  Future<void> _onEvent(matrix.Event event) async {
    if (event.type != 'm.room.message' && event.type != 'm.room.encrypted') {
      return;
    }

    final client = _client;
    if (client == null || event.senderId == client.userID) return;

    // Не шумим на старых событиях (backfill при синхронизации).
    final ageMs =
        DateTime.now().millisecondsSinceEpoch -
        event.originServerTs.millisecondsSinceEpoch;
    if (ageMs > 60000) return;

    // Уведомляем только если окно скрыто или не в фокусе.
    final visible = await windowManager.isVisible();
    final focused = await windowManager.isFocused();
    if (visible && focused) return;

    final title = event.room.getLocalizedDisplayname();
    final body = event.body.isNotEmpty ? event.body : 'Новое сообщение';

    try {
      // Звук — тем же стандартным сигналом Windows, что и системные
      // уведомления (не чаще раза в 2 секунды, защита в самом модуле).
      NotificationSound.play();
      final notif = LocalNotification(title: title, body: body);
      notif.onClick = _showWindow;
      await notif.show();
    } catch (e) {
      // ignore: avoid_print
      print('notify: $e');
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // --- окно ---
  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  // --- трей ---
  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showWindow();
        break;
      case 'exit':
        await _eventSub?.cancel();
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        break;
    }
  }
}
