// widgets/message_composer.dart — поле ввода сообщения.
// Вынесен из chat_panel.dart. Умеет: отправку текста, ответ (reply),
// редактирование своего сообщения, прикрепление файла, вставку
// изображения из буфера обмена по Ctrl+V (скриншоты!).
//
// Управление извне (из пузыря через ChatPanel):
//   final key = GlobalKey<MessageComposerState>();
//   key.currentState?.startReply(event);
//   key.currentState?.startEdit(event, currentText);
//   key.currentState?.sendFile(bytes, name);   // для drag-and-drop

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

  @override
  MessageComposerState createState() => MessageComposerState();
}

class MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  matrix.Event? _replyTo; // отвечаем на это сообщение
  matrix.Event? _editing; // редактируем это сообщение

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
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
    setState(() {
      if (_editing != null) _controller.clear();
      _replyTo = null;
      _editing = null;
    });
  }

  // Отправка файла (используется кнопкой, Ctrl+V и drag-and-drop из панели).
  Future<void> sendFile(Uint8List bytes, String name) async {
    final reply = _replyTo;
    if (reply != null) setState(() => _replyTo = null);
    await widget.room.sendFileEvent(
      matrix.MatrixFile(bytes: bytes, name: name),
      inReplyTo: reply,
    );
  }

  // ─── Отправка текста ──────────────────────────────────────────────────────

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_editing != null) {
      widget.room.sendTextEvent(text, editEventId: _editing!.eventId);
    } else {
      widget.room.sendTextEvent(text, inReplyTo: _replyTo);
    }
    _controller.clear();
    setState(() {
      _replyTo = null;
      _editing = null;
    });
  }

  // ─── Прикрепить файл кнопкой ──────────────────────────────────────────────

  Future<void> _attachFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    await sendFile(f.bytes!, f.name);
  }

  // ─── Ctrl+V: изображение из буфера или обычная вставка текста ─────────────

  Future<void> _handlePaste() async {
    final clip = SystemClipboard.instance;
    if (clip != null) {
      try {
        final reader = await clip.read();
        // Скриншот (Win+Shift+S, PrintScreen) лежит в буфере как PNG/BMP.
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
      } catch (_) {
        // Буфер недоступен — падаем в обычную текстовую вставку.
      }
    }
    await _pasteText();
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
                    // Ctrl+V — картинка из буфера или обычная вставка.
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
