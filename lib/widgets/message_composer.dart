// widgets/message_composer.dart — поле ввода сообщения.
// Вынесен из chat_panel.dart. Умеет: отправку текста, ответ (reply),
// редактирование своего сообщения, прикрепление файла, вставку
// изображения из буфера обмена по Ctrl+V (скриншоты!), вставку ФАЙЛОВ,
// скопированных в Проводнике (Ctrl+C → Ctrl+V), и черновики по чатам.
//
// Управление извне (из пузыря через ChatPanel):
//   final key = GlobalKey<MessageComposerState>();
//   key.currentState?.startReply(event);
//   key.currentState?.startEdit(event, currentText);
//   key.currentState?.sendFile(bytes, name);   // для drag-and-drop
//
// Черновики для списка чатов:
//   MessageComposer.draftFor(roomId)      // текст черновика или null
//   MessageComposer.draftsChanged         // ValueNotifier — «черновики изменились»

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:super_clipboard/super_clipboard.dart';

import '../app_theme.dart';
import 'message_bubble.dart' show eventSnippet, stripReplyFallback;

class MessageComposer extends StatefulWidget {
  final matrix.Room room;
  const MessageComposer({super.key, required this.room});

  // ─── Черновики ────────────────────────────────────────────────────────────
  // Недописанный текст по каждому чату. Живёт в памяти, пока приложение
  // запущено: переключился в другой чат и вернулся — текст на месте.
  static final Map<String, String> _drafts = {};

  /// Сигнал для списка чатов: черновики изменились, перерисуй пометки.
  static final ValueNotifier<int> draftsChanged = ValueNotifier<int>(0);

  /// Черновик чата или null, если его нет.
  static String? draftFor(String roomId) {
    final d = _drafts[roomId];
    if (d == null || d.trim().isEmpty) return null;
    return d;
  }

  @override
  MessageComposerState createState() => MessageComposerState();
}

class MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  matrix.Event? _replyTo; // отвечаем на это сообщение
  matrix.Event? _editing; // редактируем это сообщение

  @override
  void initState() {
    super.initState();
    _loadDraft(widget.room.id);
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Тот же виджет показали для другого чата — сохраняем черновик старого
    // и подставляем черновик нового.
    if (oldWidget.room.id != widget.room.id) {
      _saveDraft(oldWidget.room.id);
      _replyTo = null;
      _editing = null;
      _loadDraft(widget.room.id);
      _notifyDrafts();
    }
  }

  @override
  void dispose() {
    _saveDraft(widget.room.id);
    _notifyDrafts();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─── Черновики: сохранение и загрузка ─────────────────────────────────────

  void _onTextChanged() => _saveDraft(widget.room.id);

  // Текст редактируемого сообщения черновиком НЕ считаем — иначе после
  // отмены правки в поле вылезал бы чужой (уже отправленный) текст.
  void _saveDraft(String roomId) {
    if (_editing != null) return;
    final t = _controller.text;
    if (t.trim().isEmpty) {
      MessageComposer._drafts.remove(roomId);
    } else {
      MessageComposer._drafts[roomId] = t;
    }
  }

  void _loadDraft(String roomId) {
    final d = MessageComposer._drafts[roomId] ?? '';
    _controller.value = TextEditingValue(
      text: d,
      selection: TextSelection.collapsed(offset: d.length),
    );
  }

  // Уведомляем список чатов ПОСЛЕ текущего кадра: dispose вызывается, когда
  // дерево виджетов «заблокировано», и прямой вызов setState там запрещён.
  void _notifyDrafts() {
    Future.microtask(() => MessageComposer.draftsChanged.value++);
  }

  // ─── Публичные методы (вызываются из ChatPanel) ───────────────────────────

  void startReply(matrix.Event event) {
    setState(() {
      _editing = null;
      _replyTo = event;
    });
    _focus.requestFocus();
  }

  void startEdit(matrix.Event event, String currentText) {
    // Перед правкой текущий текст уже лежит в черновике (слушатель
    // сохраняет его на каждое изменение), так что после правки он вернётся.
    setState(() {
      _replyTo = null;
      _editing = event;
      _controller.text = currentText;
      _controller.selection = TextSelection.collapsed(
        offset: currentText.length,
      );
    });
    _focus.requestFocus();
  }

  void cancelContext() {
    final wasEditing = _editing != null;
    setState(() {
      _replyTo = null;
      _editing = null;
    });
    // После отмены правки возвращаем то, что человек писал до неё.
    if (wasEditing) _loadDraft(widget.room.id);
  }

  // Максимальный размер отправляемого файла — 5 МБ.
  // Проверка здесь закрывает все пути: скрепку, Ctrl+V и перетаскивание.
  static const int maxFileBytes = 5 * 1024 * 1024;

  // Отправка файла (используется кнопкой, Ctrl+V и drag-and-drop из панели).
  // Возвращает true, если файл принят к отправке.
  Future<bool> sendFile(Uint8List bytes, String name) async {
    if (bytes.length > maxFileBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '«$name» не отправлен: файл больше 5 МБ '
              '(${(bytes.length / 1024 / 1024).toStringAsFixed(1)} МБ)',
            ),
          ),
        );
      }
      return false;
    }
    final reply = _replyTo;
    if (reply != null) setState(() => _replyTo = null);
    await widget.room.sendFileEvent(
      matrix.MatrixFile(bytes: bytes, name: name),
      inReplyTo: reply,
    );
    return true;
  }

  // ─── Отправка текста ──────────────────────────────────────────────────────

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final editing = _editing;
    if (editing != null) {
      widget.room.sendTextEvent(text, editEventId: editing.eventId);
      setState(() {
        _replyTo = null;
        _editing = null;
      });
      // Правка отправлена — возвращаем недописанный до неё черновик.
      _loadDraft(widget.room.id);
      return;
    }
    widget.room.sendTextEvent(text, inReplyTo: _replyTo);
    _controller.clear(); // слушатель сам удалит черновик
    setState(() => _replyTo = null);
  }

  // ─── Прикрепить файл кнопкой ──────────────────────────────────────────────

  Future<void> _attachFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    await sendFile(f.bytes!, f.name);
  }

  // ─── Ctrl+V: файлы из Проводника, изображение или обычный текст ───────────

  Future<void> _handlePaste() async {
    final clip = SystemClipboard.instance;
    if (clip != null) {
      try {
        final reader = await clip.read();
        // 1) Файлы, скопированные в Проводнике (Ctrl+C на файле).
        //    Проверяем ПЕРВЫМИ: у скопированной картинки-файла в буфере
        //    лежит путь, а не PNG, и её надо отправить как есть.
        if (await _tryPasteFiles(reader)) return;
        // 2) Скриншот (Win+Shift+S, PrintScreen) лежит в буфере как PNG/BMP.
        if (reader.canProvide(Formats.png)) {
          _readAndConfirmImage(reader, Formats.png, 'png');
          return;
        }
        if (reader.canProvide(Formats.jpeg)) {
          _readAndConfirmImage(reader, Formats.jpeg, 'jpg');
          return;
        }
        if (reader.canProvide(Formats.bmp)) {
          _readAndConfirmImage(reader, Formats.bmp, 'bmp');
          return;
        }
      } catch (e) {
        // Буфер недоступен — падаем в обычную текстовую вставку.
        debugPrint('PASTE: $e');
      }
    }
    await _pasteText();
  }

  // Достаёт из буфера пути к файлам (CF_HDROP Проводника). Возвращает true,
  // если файлы в буфере были — даже если человек потом нажал «Отмена»:
  // вставлять вместо файлов текст-путь не нужно.
  Future<bool> _tryPasteFiles(ClipboardReader reader) async {
    final paths = <String>[];
    for (final item in reader.items) {
      if (!item.canProvide(Formats.fileUri)) continue;
      final uri = await item.readValue(Formats.fileUri);
      if (uri == null) continue;
      paths.add(uri.toFilePath(windows: Platform.isWindows));
    }
    if (paths.isEmpty) return false;

    // Папки не отправляем — только файлы.
    final files = <File>[];
    var skippedDirs = 0;
    for (final p in paths) {
      if (await FileSystemEntity.isDirectory(p)) {
        skippedDirs++;
      } else {
        files.add(File(p));
      }
    }
    if (!mounted) return true;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Папки отправлять нельзя — только файлы')),
      );
      return true;
    }

    final ok = await _confirmFiles(files, skippedDirs);
    if (ok != true || !mounted) return true;

    var sent = 0;
    for (final f in files) {
      final name = f.path.split(RegExp(r'[\\/]')).last;
      try {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) throw Exception('файл пустой');
        if (await sendFile(bytes, name.isEmpty ? 'file' : name)) sent++;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('«$name» не отправлен: $e')));
        }
      }
    }
    if (mounted && sent > 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Отправлено файлов: $sent')));
    }
    return true;
  }

  // Подтверждение перед отправкой вставленных файлов — чтобы случайный
  // Ctrl+V не отправил в чат то, что лежало в буфере с утра.
  Future<bool?> _confirmFiles(List<File> files, int skippedDirs) async {
    String sizeOf(File f) {
      try {
        final mb = f.lengthSync() / 1024 / 1024;
        return mb < 0.1 ? '< 0,1 МБ' : '${mb.toStringAsFixed(1)} МБ';
      } catch (_) {
        return '';
      }
    }

    final shown = files.take(10).toList();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          files.length == 1
              ? 'Отправить файл?'
              : 'Отправить файлы (${files.length})?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 18,
                        color: T.steel,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.path.split(RegExp(r'[\\/]')).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sizeOf(f),
                        style: const TextStyle(fontSize: 12, color: T.textSec),
                      ),
                    ],
                  ),
                ),
              if (files.length > shown.length)
                Text(
                  '…и ещё ${files.length - shown.length}',
                  style: const TextStyle(fontSize: 12, color: T.textSec),
                ),
              if (skippedDirs > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Папки пропущены: $skippedDirs',
                    style: const TextStyle(fontSize: 12, color: T.textSec),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Файлы больше 5 МБ отправлены не будут.',
                  style: TextStyle(fontSize: 12, color: T.textSec),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: T.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
  }

  void _readAndConfirmImage(
    ClipboardReader reader,
    FileFormat format,
    String ext,
  ) {
    reader.getFile(format, (file) async {
      final bytes = await file.readAll();
      if (!mounted || bytes.isEmpty) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отправить изображение?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: T.accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отправить'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'image_${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.$ext';
      try {
        await sendFile(bytes, name);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось отправить изображение: $e')),
          );
        }
      }
    });
  }

  // Обычная вставка текста в позицию курсора (раз мы перехватили Ctrl+V,
  // стандартную вставку надо воспроизвести самим).
  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _controller.text = text.replaceRange(start, end, t);
    _controller.selection = TextSelection.collapsed(offset: start + t.length);
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  String _bannerName(matrix.Event e) => widget.room
      .unsafeGetUserFromMemoryOrFallback(e.senderId)
      .calcDisplayname();

  Widget _contextBanner() {
    final editing = _editing;
    final replyTo = _replyTo;
    final isEdit = editing != null;
    final src = isEdit ? editing : replyTo!;
    return Container(
      color: T.panelAlt,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(isEdit ? Icons.edit : Icons.reply, size: 18, color: T.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F9),
                borderRadius: BorderRadius.circular(8),
                border: const Border(left: BorderSide(color: T.gold, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? 'Редактирование' : _bannerName(src),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: T.steel,
                    ),
                  ),
                  Text(
                    isEdit ? stripReplyFallback(src.body) : eventSnippet(src),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: T.textSec),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: isEdit ? 'Отменить редактирование' : 'Отменить ответ',
            icon: const Icon(Icons.close, size: 18, color: T.hint),
            onPressed: cancelContext,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyTo != null || _editing != null) _contextBanner(),
        Container(
          color: T.panelAlt,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Прикрепить файл',
                icon: const Icon(Icons.attach_file, color: T.hint),
                onPressed: _attachFile,
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
                    // Esc — отменить ответ/редактирование.
                    const SingleActivator(LogicalKeyboardKey.escape):
                        cancelContext,
                    // Ctrl+V — файлы, картинка из буфера или обычная вставка.
                    const SingleActivator(
                      LogicalKeyboardKey.keyV,
                      control: true,
                    ): _handlePaste,
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _editing != null
                          ? 'Изменить сообщение…'
                          : 'Сообщение…',
                      hintStyle: const TextStyle(color: T.hint),
                      filled: true,
                      fillColor: const Color(0xFFF2F5F9),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: T.gold),
                icon: Icon(
                  _editing != null ? Icons.check : Icons.arrow_upward,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
