// services/media_archive.dart — фоновое наполнение локального архива вложений.
//
// Зачем это нужно.
// На сервере файлы хранятся ограниченный срок (media_retention в Synapse),
// а тексты — вечно. Чтобы вложения не пропадали у людей вместе с ретенцией,
// приложение складывает их на диск пользователя навсегда.
//
// Стратегия «гибрид»:
//   • картинки и небольшие файлы (до kAutoArchiveBytes) — скачиваются САМИ,
//     фоном, как только чат открыт. Человек мог не открыть вложение, но оно
//     у него всё равно сохранится;
//   • крупные файлы — только когда пользователь реально их открыл. Иначе
//     одно видео на 500 МБ разъедется по дискам всех сотрудников.
//
// Само сохранение делает matrix SDK: downloadAndDecryptAttachment() кладёт
// файл в fileStorageLocation (см. matrix_service.dart). Здесь мы лишь
// аккуратно, по очереди, дёргаем загрузку для нужных событий.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Максимальный размер файла, который вообще попадает в локальный архив.
/// Всё, что крупнее, каждый раз качается с сервера (и пропадёт после
/// ретенции) — иначе одно видео забьёт диск сотрудника.
const int kMaxArchivedFileBytes = 100 * 1024 * 1024; // 100 МБ

/// Порог «мелкого» файла для фоновой автозагрузки. Такие вложения (и все
/// картинки) приложение скачивает само, не дожидаясь, пока их откроют, —
/// чтобы после ретенции они не пропали у тех, кто просто не успел открыть.
const int kAutoArchiveBytes = 5 * 1024 * 1024; // 5 МБ

class MediaArchive {
  final matrix.Client client;

  MediaArchive(this.client);

  // mxc-ссылки, которые уже обработаны в этом сеансе (успешно или нет) —
  // чтобы не пытаться качать одно и то же по кругу на каждом обновлении ленты.
  final Set<String> _seen = <String>{};

  // Очередь на скачивание и флаг работающего обработчика.
  final Queue<matrix.Event> _queue = Queue<matrix.Event>();
  bool _working = false;

  /// Ставит в очередь вложения, которые подходят под автоархивирование.
  /// Вызывается при каждом обновлении ленты чата — дешёвая операция:
  /// всё уже виденное отсекается по _seen.
  void enqueue(Iterable<matrix.Event> events) {
    for (final event in events) {
      if (!_shouldAutoArchive(event)) continue;
      final url = event.attachmentMxcUrl?.toString();
      if (url == null || _seen.contains(url)) continue;
      _seen.add(url);
      _queue.add(event);
    }
    if (_queue.isNotEmpty) unawaited(_drain());
  }

  /// Подходит ли вложение под фоновую загрузку.
  /// Крупные файлы сюда не попадают — они архивируются только по факту
  /// открытия пользователем.
  bool _shouldAutoArchive(matrix.Event event) {
    if (event.type != matrix.EventTypes.Message) return false;
    if (!event.hasAttachment) return false;
    if (event.redacted) return false;

    final size = event.infoMap['size'];
    // Размер не указан — не рискуем тянуть неизвестно что в фоне.
    if (size is! int) return false;
    if (size > kAutoArchiveBytes) return false;

    // Картинки берём всегда (в пределах порога), прочие типы — тоже,
    // раз они мелкие. Стикеры и служебное не трогаем.
    const wanted = {
      matrix.MessageTypes.Image,
      matrix.MessageTypes.File,
      matrix.MessageTypes.Audio,
      matrix.MessageTypes.Video,
    };
    return wanted.contains(event.messageType);
  }

  // Разбирает очередь строго по одному файлу за раз: фоновая задача не должна
  // мешать открытию чатов и грузить сервер параллельными запросами.
  Future<void> _drain() async {
    if (_working) return;
    _working = true;
    try {
      while (_queue.isNotEmpty) {
        final event = _queue.removeFirst();
        final url = event.attachmentMxcUrl;
        if (url == null) continue;
        try {
          // Уже в архиве — второй раз не качаем.
          final cached = await client.database.getFile(url);
          if (cached != null) continue;

          // Скачивание само положит файл в архив (fileStorageLocation).
          await event.downloadAndDecryptAttachment();
        } catch (e) {
          // Файл мог быть уже удалён с сервера по ретенции, или нет сети.
          // Это не ошибка приложения — просто идём дальше.
          debugPrint('Архив вложений, пропуск ${event.eventId}: $e');
        }
        // Небольшая пауза, чтобы не устраивать шторм запросов к серверу.
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      _working = false;
    }
  }

  /// Лежит ли вложение этого события в локальном архиве.
  /// Нужно интерфейсу, чтобы отличить «файл удалён с сервера, но он у вас
  /// сохранён» от «файла нет нигде».
  Future<bool> isArchived(matrix.Event event) async {
    final url = event.attachmentMxcUrl;
    if (url == null) return false;
    try {
      return await client.database.getFile(url) != null;
    } catch (_) {
      return false;
    }
  }
}
