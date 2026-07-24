// widgets/file_preview.dart — вложения в чате.
// FileAttachment — плитка файла внутри пузыря сообщения (иконка + имя + размер).
//   • Плитку можно СХВАТИТЬ И ПЕРЕТАЩИТЬ из чата на рабочий стол / в папку /
//     в письмо Outlook — файл скачается прямо туда (super_drag_and_drop).
// По клику открывается окно-превью в духе Outlook:
//   • картинки показываются прямо внутри;
//   • PDF листается ПРЯМО В ОКНЕ (pdfrx) — окно почти во весь экран;
//   • офисные/прочие файлы — карточка с иконкой, именем, размером;
//   • «Открыть» — открыть в Word/Excel из ВРЕМЕННОЙ папки (в «Загрузки» не качается);
//   • «Скачать» — сохранить в выбранное место.
//
// Если компилятор не найдёт downloadAndDecryptAttachment — добавь строку:
//   import 'package:matrix/encryption.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:super_clipboard/super_clipboard.dart' show SimpleFileFormat;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:xml/xml.dart';

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

// Универсальный формат «просто файл» для перетаскивания наружу —
// в пакете нет готового octet-stream, объявляем сами.
const SimpleFileFormat _genericFile = SimpleFileFormat(
  uniformTypeIdentifiers: ['public.data'],
  mimeTypes: ['application/octet-stream'],
);

// Формат для перетаскивания наружу: где можем — точный тип,
// для остальных — универсальный «поток байтов».
FileFormat _dragFormatFor(String ext) {
  switch (ext) {
    case 'pdf':
      return Formats.pdf;
    case 'png':
      return Formats.png;
    case 'jpg':
    case 'jpeg':
      return Formats.jpeg;
    case 'gif':
      return Formats.gif;
    case 'webp':
      return Formats.webp;
    case 'zip':
      return Formats.zip;
    default:
      return _genericFile;
  }
}

// ─────────────────── упрощённый разбор DOCX (как в Outlook) ───────────────────
// DOCX — это zip-архив; текст лежит в word/document.xml.
// Вытаскиваем абзацы (с жирным/курсивом и заголовками) и таблицы построчно.
// Точную вёрстку Word воспроизвести нельзя — это именно ПРЕДПРОСМОТР.

class _DocxRun {
  final String text;
  final bool bold;
  final bool italic;
  const _DocxRun(this.text, this.bold, this.italic);
}

class _DocxBlock {
  final List<_DocxRun> runs;
  final int heading; // 0 — обычный абзац, 1..9 — уровень заголовка
  final bool isTableRow;
  const _DocxBlock(this.runs, {this.heading = 0, this.isTableRow = false});

  String get plain => runs.map((r) => r.text).join();
}

List<_DocxBlock>? _parseDocx(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) return null;
    final xmlText = utf8.decode(entry.content as List<int>);
    final doc = XmlDocument.parse(xmlText);
    final bodies = doc.findAllElements('w:body');
    if (bodies.isEmpty) return null;
    final body = bodies.first;

    final blocks = <_DocxBlock>[];
    var totalChars = 0;
    const maxBlocks = 400;
    const maxChars = 40000;

    _DocxBlock parseParagraph(XmlElement p) {
      var heading = 0;
      final style =
          p
              .getElement('w:pPr')
              ?.getElement('w:pStyle')
              ?.getAttribute('w:val') ??
          '';
      final s = style.toLowerCase();
      if (s.startsWith('heading')) {
        heading = int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
        if (heading > 9) heading = 9;
      }
      final runs = <_DocxRun>[];
      for (final r in p.findElements('w:r')) {
        final rPr = r.getElement('w:rPr');
        final bold = rPr?.getElement('w:b') != null;
        final italic = rPr?.getElement('w:i') != null;
        final buf = StringBuffer();
        for (final child in r.children) {
          if (child is XmlElement) {
            switch (child.name.local) {
              case 't':
                buf.write(child.innerText);
                break;
              case 'br':
                buf.write('\n');
                break;
              case 'tab':
                buf.write('    ');
                break;
            }
          }
        }
        if (buf.isNotEmpty) {
          runs.add(_DocxRun(buf.toString(), bold, italic));
        }
      }
      return _DocxBlock(runs, heading: heading);
    }

    void addBlock(_DocxBlock b) {
      if (blocks.length >= maxBlocks || totalChars >= maxChars) return;
      totalChars += b.plain.length;
      blocks.add(b);
    }

    for (final node in body.children) {
      if (node is! XmlElement) continue;
      if (blocks.length >= maxBlocks || totalChars >= maxChars) break;
      switch (node.name.local) {
        case 'p':
          addBlock(parseParagraph(node));
          break;
        case 'tbl':
          for (final tr in node.findAllElements('w:tr')) {
            final cells = <String>[];
            for (final tc in tr.findElements('w:tc')) {
              final cellText = tc
                  .findAllElements('w:t')
                  .map((t) => t.innerText)
                  .join();
              cells.add(cellText.trim());
            }
            addBlock(
              _DocxBlock([
                _DocxRun(cells.join('  |  '), false, false),
              ], isTableRow: true),
            );
          }
          break;
      }
    }

    final truncated = blocks.length >= maxBlocks || totalChars >= maxChars;
    if (truncated) {
      blocks.add(
        const _DocxBlock([
          _DocxRun(
            '… документ показан не полностью — «Открыть» для Word',
            false,
            true,
          ),
        ]),
      );
    }
    return blocks;
  } catch (_) {
    return null;
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

    final tile = Material(
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

    // Перетаскивание файла ИЗ чата наружу (рабочий стол, папка, Outlook).
    // Содержимое отдаётся как «виртуальный файл»: скачивание с сервера
    // начинается только в момент, когда пользователь ОТПУСТИЛ файл
    // в месте назначения — само перетаскивание стартует мгновенно.
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      dragItemProvider: (request) async {
        final item = DragItem(suggestedName: name);
        item.addVirtualFile(
          format: _dragFormatFor(ext),
          provider: (sinkProvider, progress) async {
            try {
              final mf = await event.downloadAndDecryptAttachment();
              final sink = sinkProvider(fileSize: mf.bytes.length);
              sink.add(mf.bytes);
              sink.close();
            } catch (_) {
              // Сеть/сервер недоступны — приёмник получит пустую передачу;
              // пользователь просто повторит перетаскивание.
            }
          },
        );
        return item;
      },
      child: DraggableWidget(child: tile),
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
  bool get _isPdf => _ext == 'pdf';

  // Разобранные блоки DOCX (null — не docx или разобрать не удалось).
  List<_DocxBlock>? _docxBlocks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mf = await widget.event.downloadAndDecryptAttachment();
      if (!mounted) return;
      List<_DocxBlock>? docx;
      if (_extOf(_fileNameOf(widget.event)) == 'docx') {
        docx = _parseDocx(mf.bytes);
      }
      setState(() {
        _bytes = mf.bytes;
        _docxBlocks = docx;
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
    // PDF, картинкам и DOCX-превью даём почти весь экран,
    // остальным — компактную карточку.
    final media = MediaQuery.of(context).size;
    final big = _isPdf || _isImage || _docxBlocks != null;
    final constraints = BoxConstraints(
      maxWidth: big ? media.width * 0.85 : 460,
      maxHeight: big ? media.height * 0.88 : 560,
    );

    return Dialog(
      backgroundColor: T.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: constraints,
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

  // Отрисовка одного блока DOCX-превью.
  Widget _docxBlockWidget(_DocxBlock b) {
    // Строка таблицы — серым фоном, моноширинно-компактно.
    if (b.isTableRow) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5F9),
          border: Border.all(color: T.border, width: 0.5),
        ),
        child: Text(
          b.plain,
          style: const TextStyle(fontSize: 13, color: T.text, height: 1.3),
        ),
      );
    }
    // Пустой абзац — просто отступ.
    if (b.plain.trim().isEmpty) return const SizedBox(height: 10);

    final isHeading = b.heading > 0;
    final baseSize = isHeading ? (b.heading == 1 ? 19.0 : 16.5) : 14.0;
    return Padding(
      padding: EdgeInsets.only(
        top: isHeading ? 14 : 3,
        bottom: isHeading ? 6 : 3,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            for (final r in b.runs)
              TextSpan(
                text: r.text,
                style: TextStyle(
                  fontWeight: (isHeading || r.bold)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
                ),
              ),
          ],
        ),
        style: TextStyle(fontSize: baseSize, color: T.text, height: 1.45),
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
    // PDF — листается прямо в окне.
    if (_isPdf && _bytes != null) {
      return Container(
        color: const Color(0xFFE9ECF1),
        child: PdfViewer.data(_bytes!, sourceName: _name),
      );
    }
    // DOCX — упрощённый предпросмотр текста (как в Outlook).
    if (_docxBlocks != null) {
      return Container(
        color: Colors.white,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          itemCount: _docxBlocks!.length,
          itemBuilder: (_, i) => _docxBlockWidget(_docxBlocks![i]),
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
