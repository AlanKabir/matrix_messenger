// screens/settings_screen.dart — экран «Настройки».
// Внутри: карточка профиля с ФОТО (можно загрузить своё),
// «Автозапуск при входе в Windows», «Устройства и сеансы», «Выйти».
//
// ФИО здесь НЕ редактируется: имя приходит из Active Directory через SSO,
// менять его нужно в AD (или временно в админ-панели Synapse).
//
// ВАЖНО: пункты «Устройства и сеансы» и «Выйти из аккаунта» сейчас СКРЫТЫ.
// Управляется одной строкой ниже — showAccountControls.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/autostart_service.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'sessions_screen.dart';

// ─────────────────────────────────────────────────────────────
// ПЕРЕКЛЮЧАТЕЛЬ. Поставь true, чтобы вернуть «Устройства и сеансы»
// и «Выйти из аккаунта». Сейчас скрыто (false).
bool showAccountControls = false;
// ─────────────────────────────────────────────────────────────

// Максимальный размер фото для аватара.
const int _maxAvatarBytes = 5 * 1024 * 1024;

class SettingsScreen extends StatefulWidget {
  final MatrixService service;
  const SettingsScreen({super.key, required this.service});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  matrix.Client get _client => widget.service.client!;

  late Future<matrix.Profile> _profileFuture;
  bool _busy = false;

  // Текущее состояние автозапуска (прочитано из реестра при старте).
  bool _autostart = AutostartService.instance.enabled;

  // Размер локального архива вложений (null — ещё считается).
  ({int files, int bytes})? _archiveStats;

  @override
  void initState() {
    super.initState();
    _profileFuture = _client.fetchOwnProfile();
    _loadArchiveStats();
  }

  // --- локальный архив вложений ---------------------------------------------

  Future<void> _loadArchiveStats() async {
    final stats = await widget.service.archiveStats();
    if (mounted) setState(() => _archiveStats = stats);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _confirmClearArchive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить архив вложений?'),
        content: const Text(
          'Будут удалены все сохранённые на этом компьютере файлы.\n\n'
          'Те вложения, срок хранения которых на сервере уже истёк, '
          'восстановить будет невозможно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.clearArchive();
    await _loadArchiveStats();
    _snack('Архив вложений очищен');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Загрузка фотографии на аватар: выбор файла → загрузка на сервер →
  // привязка к профилю. Фото сразу видно всем: в чатах, поиске, группах.
  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Выберите фотографию',
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.bytes!.length > _maxAvatarBytes) {
      _snack('Фото больше 5 МБ — выберите файл поменьше');
      return;
    }
    setState(() => _busy = true);
    try {
      // setAvatar сам загружает файл и привязывает его к профилю.
      await _client.setAvatar(matrix.MatrixFile(bytes: f.bytes!, name: f.name));
      if (!mounted) return;
      setState(() => _profileFuture = _client.fetchOwnProfile());
      _snack('Фотография обновлена');
    } catch (e) {
      _snack('Не удалось загрузить фото: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutostart(bool value) async {
    final result = await AutostartService.instance.setEnabled(value);
    if (mounted) setState(() => _autostart = result);
  }

  Future<void> _logout(BuildContext context) async {
    await widget.service.logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _openSessions(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionsScreen(
          client: _client,
          onLogoutCurrentDevice: () {
            Navigator.of(context).pop(); // закрыть экран сеансов
            _logout(context);
          },
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Придётся снова войти через доменную учётную запись.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) _logout(context);
  }

  @override
  Widget build(BuildContext context) {
    final me = _client.userID ?? '';
    return Scaffold(
      backgroundColor: T.panel,
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: T.accent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              // --- карточка профиля с фото ---
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: T.panelAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: T.border),
                ),
                child: FutureBuilder<matrix.Profile>(
                  future: _profileFuture,
                  builder: (_, snap) {
                    final name = snap.data?.displayName ?? me;
                    return Row(
                      children: [
                        // Аватар с кнопкой-камерой: клик — выбрать фото.
                        Stack(
                          children: [
                            InitialsAvatar(
                              name: name,
                              radius: 34,
                              mxcUrl: snap.data?.avatarUrl,
                              client: _client,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Material(
                                color: T.gold,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _busy ? null : _pickAvatar,
                                  child: const Padding(
                                    padding: EdgeInsets.all(5),
                                    child: Icon(
                                      Icons.photo_camera,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: T.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextButton.icon(
                                onPressed: _busy ? null : _pickAvatar,
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                ),
                                label: const Text('Изменить фото'),
                                style: TextButton.styleFrom(
                                  foregroundColor: T.accent,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // --- автозапуск при входе в Windows ---
              const SizedBox(height: 22),
              _group([
                SwitchListTile(
                  value: _autostart,
                  onChanged: _toggleAutostart,
                  activeThumbColor: T.accent,
                  secondary: const Icon(
                    Icons.power_settings_new,
                    color: T.accent,
                  ),
                  title: const Text(
                    'Запускать при входе в Windows',
                    style: TextStyle(
                      color: T.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: const Text(
                    'Мессенджер откроется автоматически после включения компьютера',
                    style: TextStyle(fontSize: 12.5, color: T.textSec),
                  ),
                ),
              ]),

              // --- локальный архив вложений ---
              const SizedBox(height: 22),
              _group([
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined,
                      color: T.accent),
                  title: const Text(
                    'Архив вложений на этом компьютере',
                    style: TextStyle(
                      color: T.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _archiveStats == null
                        ? 'Подсчёт…'
                        : 'Файлов: ${_archiveStats!.files} · '
                            '${_formatBytes(_archiveStats!.bytes)}\n'
                            'На сервере вложения хранятся ограниченный срок, '
                            'здесь они остаются навсегда.',
                    style: const TextStyle(fontSize: 12.5, color: T.textSec),
                  ),
                  isThreeLine: _archiveStats != null,
                  trailing: IconButton(
                    tooltip: 'Обновить',
                    icon: const Icon(Icons.refresh, color: T.hint, size: 20),
                    onPressed: _loadArchiveStats,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined,
                      color: Colors.red),
                  title: const Text(
                    'Очистить архив вложений',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: const Text(
                    'Освободит место, но файлы, уже удалённые с сервера, '
                    'восстановить будет нельзя',
                    style: TextStyle(fontSize: 12.5, color: T.textSec),
                  ),
                  onTap: _confirmClearArchive,
                ),
              ]),

              // --- устройства и сеансы (скрыто через showAccountControls) ---
              if (showAccountControls) ...[
                const SizedBox(height: 22),
                _group([
                  _tile(
                    icon: Icons.devices,
                    label: 'Устройства и сеансы',
                    onTap: () => _openSessions(context),
                  ),
                ]),
              ],

              // --- выход (скрыто через showAccountControls) ---
              if (showAccountControls) ...[
                const SizedBox(height: 22),
                _group([
                  _tile(
                    icon: Icons.logout,
                    label: 'Выйти из аккаунта',
                    danger: true,
                    onTap: () => _confirmLogout(context),
                  ),
                ]),
              ],
            ],
          ),
          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2, color: T.accent),
            ),
        ],
      ),
    );
  }

  Widget _group(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: T.panelAlt,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: T.border),
    ),
    child: Column(children: children),
  );

  Widget _tile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: danger ? Colors.red : T.accent),
      title: Text(
        label,
        style: TextStyle(
          color: danger ? Colors.red : T.text,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: danger
          ? null
          : const Icon(Icons.chevron_right, color: T.hint, size: 20),
      onTap: onTap,
    );
  }
}
