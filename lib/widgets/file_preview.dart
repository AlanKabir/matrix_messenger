// widgets/file_preview.dart — вложения в чате.
// FileAttachment — плитка файла внутри пузыря сообщения (иконка + имя + размер).
// По клику открывается окно-превью в духе Outlook:
//   • картинки показываются прямо внутри;
//   • офисные/прочие файлы — карточка с иконкой, именем, размером;
//   • «Открыть» — открыть в Word/Excel из ВРЕМЕННОЙ папки (в «Загрузки» не качается);
//   • «Скачать» — сохранить в выбранное место.
//
// Если компилятор не найдёт downloadAndDecryptAttachment — добавь строку:
//   import 'package:matrix/encryption.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';

// ─────────────────────────── helpers ───────────────────────────

String _fileNameOf(matrix.Event e) {
  final fromContent = e.content['filename'];
  if (fromContent is String && fromContent.isNotEmpty) return fromContent;
  if (e.body.isNotEmpty) return e.body;
  return 'файл';
}

int? _sizeOf(matrix.Event e) {
  final info = e.content['info'];
  if (info is Map && info['size'] is num) return (info['size'] as num).toInt();
  return null;
}

String _extOf(String name) {
  final i = name.lastIndexOf('.');
  return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
}

bool _isImageExt(String ext) =>
    const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext);

String _humanSize(int? bytes) {
  if (bytes == null) return '';
  const units = ['Б', 'КБ', 'МБ', 'ГБ'];
  double s = bytes.toDouble();
  int u = 0;
  while (s >= 1024 && u < units.length - 1) {
    s /= 1024;
    u++;
  }
  final str = u == 0 ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
  return '$str ${units[u]}';
}

// Иконка+цвет по расширению.
Widget _fileGlyph(String ext, {double size = 22}) {
  IconData icon;
  Color color;
  switch (ext) {
    case 'doc':
    case 'docx':
    case 'rtf':
      icon = Icons.description;
      color = const Color(0xFF2B579A); // Word синий
      break;
    case 'xls':
    case 'xlsx':
    case 'csv':
      icon = Icons.table_chart;
      color = const Color(0xFF217346); // Excel зелёный
      break;
    case 'ppt':
    case 'pptx':
      icon = Icons.slideshow;
      color = const Color(0xFFC43E1C); // PowerPoint оранжевый
      break;
    case 'pdf':
      icon = Icons.picture_as_pdf;
      color = const Color(0xFFD32F2F);
      break;
    case 'zip':
    case 'rar':
    case '7z':
      icon = Icons.folder_zip;
      color = const Color(0xFF8D6E63);
      break;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
      icon = Icons.image;
      color = const Color(0xFF3B6EA5);
      break;
    default:
      icon = Icons.insert_drive_file;
      color = T.hint;
  }
  return Icon(icon, color: color, size: size);
}

// Понятное название типа для подписи.
String _typeLabel(String ext) {
  switch (ext) {
    case 'doc':
    case 'docx':
      return 'Документ Word';
    case 'xls':
    case 'xlsx':
      return 'Таблица Excel';
    case 'ppt':
    case 'pptx':
      return 'Презентация PowerPoint';
    case 'pdf':
      return 'Документ PDF';
    case 'csv':
      return 'Таблица CSV';
    default:
      return ext.isEmpty ? 'Файл' : 'Файл .$ext';
  }
}

// ─────────────────────── плитка в пузыре ───────────────────────

class FileAttachment extends StatelessWidget {
  final matrix.Event event;
  const FileAttachment({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final name = _fileNameOf(event);
    final ext = _extOf(name);
    final size = _sizeOf(event);
    final subtitle = [
      if (ext.isNotEmpty) ext.toUpperCase(),
      if (_humanSize(size).isNotEmpty) _humanSize(size),
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showFilePreview(context, event),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: T.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _fileGlyph(ext, size: 24),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: T.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 11.5, color: T.hint),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── окно-превью ───────────────────────

Future<void> showFilePreview(BuildContext context, matrix.Event event) {
  return showDialog(
    context: context,
    builder: (_) => _FilePreviewDialog(event: event),
  );
}

class _FilePreviewDialog extends StatefulWidget {
  final matrix.Event event;
  const _FilePreviewDialog({required this.event});

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _busy = false; // идёт открытие/сохранение
  String? _error;

  String get _name => _fileNameOf(widget.event);
  String get _ext => _extOf(_name);
  int? get _size => _sizeOf(widget.event);
  bool get _isImage => _isImageExt(_ext);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mf = await widget.event.downloadAndDecryptAttachment();
      if (!mounted) return;
      setState(() {
        _bytes = mf.bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить файл';
        _loading = false;
      });
    }
  }

  // Записать во временную папку и вернуть путь.
  Future<String> _writeTemp() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$_name';
    await File(path).writeAsBytes(_bytes!, flush: true);
    return path;
  }

  // Открыть системным приложением (Word/Excel/…), файл лежит во временной папке.
  Future<void> _open() async {
    if (_bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await _writeTemp();
      await OpenFilex.open(path);
    } catch (_) {
      _snack('Не удалось открыть файл');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Сохранить в выбранное пользователем место.
  Future<void> _download() async {
    if (_bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить файл',
        fileName: _name,
      );
      if (path != null) {
        await File(path).writeAsBytes(_bytes!, flush: true);
        _snack('Сохранено');
      }
    } catch (_) {
      _snack('Не удалось сохранить файл');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: T.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- шапка ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  _fileGlyph(_ext, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: T.text,
                          ),
                        ),
                        Text(
                          [
                            _typeLabel(_ext),
                            if (_humanSize(_size).isNotEmpty) _humanSize(_size),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: T.hint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: T.hint),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: T.border),
            // ---- тело ----
            Flexible(child: _buildBody()),
            const Divider(height: 1, color: T.border),
            // ---- кнопки ----
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_bytes == null || _busy) ? null : _download,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Скачать'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: T.accent,
                        side: const BorderSide(color: T.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_bytes == null || _busy) ? null : _open,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Открыть'),
                      style: FilledButton.styleFrom(
                        backgroundColor: T.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: T.accent)),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    // Картинки — показываем прямо внутри.
    if (_isImage && _bytes != null) {
      return Container(
        color: const Color(0xFF0E1117),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.memory(_bytes!, fit: BoxFit.contain),
        ),
      );
    }
    // Офисные/прочие — карточка с крупной иконкой.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _fileGlyph(_ext, size: 72),
          const SizedBox(height: 16),
          Text(
            _typeLabel(_ext),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: T.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Предпросмотр содержимого недоступен.\n'
            'Нажмите «Открыть», чтобы просмотреть файл в приложении.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: T.hint, height: 1.4),
          ),
        ],
      ),
    );
  }
}
