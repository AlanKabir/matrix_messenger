// app_theme.dart — вся палитра приложения в одном месте.
// Активна ваша фирменная тема ABYROY (темная, неоново-зеленая).
// Для светлой WhatsApp-темы значения указаны в комментариях справа.

import 'package:flutter/material.dart';

class T {
  static const bg        = Color(0xFF121212); // WA: Colors.white
  static const panel     = Color(0xFF161616); // WA: 0xFFF0F2F5
  static const panelAlt  = Color(0xFF0D0D0D); // WA: Colors.white
  static const inputFill = Color(0xFF1F1F1F); // WA: Colors.white
  static const border    = Color(0xFF262626); // WA: 0xFFE0E0E0

  static const accent     = Color(0xFF00E676); // WA: 0xFF128C7E
  static const accentDark = Color(0xFF0D3823); // WA: 0xFF128C7E
  static const selected   = Color(0xFF1E2E25); // WA: 0xFFF0F6F4

  static const ownBubble = Color(0xFF0D3823); // WA: 0xFFD9FDD3
  static const inBubble  = Color(0xFF1E1E1E); // WA: Colors.white
  static const feedBg    = Color(0xFF121212); // WA: 0xFFEFEAE2

  static const text    = Colors.white;        // WA: 0xFF111111
  static const textSec = Color(0xFF8A8A8A);
  static const hint    = Color(0xFF555555);

  static const tickSending = Color(0xFF7A7A7A);
  static const tickSent    = Color(0xFF7A7A7A); // 1 галочка: на сервере
  static const tickRead    = Color(0xFF00E676); // прочитано (WA: 0xFF53BDEB)

  static const unreadBadge     = Color(0xFF00E676);
  static const unreadBadgeText = Colors.black;
}
