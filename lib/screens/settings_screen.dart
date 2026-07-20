// screens/settings_screen.dart — экран «Настройки».
// Внутри: карточка профиля, «Устройства и сеансы», «Выйти из аккаунта».

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/matrix_service.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'sessions_screen.dart';

class SettingsScreen extends StatelessWidget {
  final MatrixService service;
  const SettingsScreen({super.key, required this.service});

  matrix.Client get _client => service.client!;

  Future<void> _logout(BuildContext context) async {
    await service.logout();
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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // --- карточка профиля ---
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: T.panelAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: T.border),
            ),
            child: FutureBuilder<matrix.Profile>(
              future: _client.fetchOwnProfile(),
              builder: (_, snap) {
                final name = snap.data?.displayName ?? me;
                return Row(
                  children: [
                    InitialsAvatar(name: name, radius: 28),
                    const SizedBox(width: 14),
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
                          const SizedBox(height: 2),
                          Text(
                            me,
                            style: const TextStyle(
                              fontSize: 13,
                              color: T.textSec,
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
          const SizedBox(height: 22),

          // --- устройства и сеансы ---
          _group([
            _tile(
              icon: Icons.devices,
              label: 'Устройства и сеансы',
              onTap: () => _openSessions(context),
            ),
          ]),
          const SizedBox(height: 22),

          // --- выход ---
          _group([
            _tile(
              icon: Icons.logout,
              label: 'Выйти из аккаунта',
              danger: true,
              onTap: () => _confirmLogout(context),
            ),
          ]),
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
