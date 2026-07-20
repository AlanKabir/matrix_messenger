// app_theme.dart — вся палитра приложения в одном месте.
// Тема SGO: светлая, фирменный синий #17376B + золотой акцент #C79A2E.
// (Прежние значения ABYROY/WhatsApp оставлены в комментариях справа.)

import 'package:flutter/material.dart';

class T {
  // --- поверхности ---
  static const bg = Colors.white; // фон приложения
  static const panel = Color(0xFFF2F5F9); // боковая панель (серебристый)
  static const panelAlt = Colors.white; // шапки чата/композер
  static const inputFill = Colors.white; // поля ввода
  static const border = Color(0xFFE2E7EE); // тонкие разделители

  // --- акценты ---
  static const accent = Color(0xFF17376B); // основной синий (герб)
  static const accentDark = Color(0xFF0F2547); // тёмный синий (нажатия/hover)
  static const gold = Color(0xFFC79A2E); // золотой акцент (кнопки/бейджи)
  static const steel = Color(
    0xFF3B6EA5,
  ); // сталь-синий (статусы, часть аватаров)
  static const selected = Color(0xFFEAF0F8); // выделенный чат в списке

  // --- пузыри переписки ---
  static const ownBubble = Color(0xFF17376B); // свои сообщения (синие)
  static const inBubble = Color(0xFFECEFF3); // чужие (светло-серые)
  static const feedBg = Color(0xFFF6F8FC); // фон ленты сообщений

  // --- текст ---
  static const text = Color(0xFF1D2530); // основной
  static const textSec = Color(0xFF7A8699); // второстепенный (превью, статусы)
  static const hint = Color(0xFF8A94A3); // подсказки, время

  // --- галочки статуса ---
  static const tickSending = Color(0xFF8A94A3);
  static const tickSent = Color(0xFF8A94A3); // 1 галочка: на сервере
  static const tickRead = Color(0xFF3B6EA5); // прочитано (сталь-синий)

  // --- бейдж непрочитанного ---
  static const unreadBadge = Color(0xFFC79A2E); // золотой
  static const unreadBadgeText = Colors.white;

  // --- цвета аватаров (по инициалам, из фирменной палитры) ---
  static const avatarColors = <Color>[
    Color(0xFF17376B), // синий
    Color(0xFF3B6EA5), // сталь
    Color(0xFF7C8698), // серо-стальной
    Color(0xFFC79A2E), // золото
    Color(0xFF2E5E8C), // средний синий
  ];

  // --- готовая ThemeData на этой палитре ---
  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      primary: accent,
      secondary: gold,
      surface: bg,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Segoe UI',
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: const TextTheme().apply(bodyColor: text, displayColor: text),
      iconTheme: const IconThemeData(color: accent),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
