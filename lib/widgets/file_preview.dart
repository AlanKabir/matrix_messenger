// widgets/file_preview.dart — inline-предпросмотр вложений Matrix прямо
// в пузыре. Скачивает и (при E2EE) расшифровывает вложение через SDK,
// рендерит локальными пакетами — без интернет-сервисов:
//   PDF → pdfrx (pdfium), XLSX → excel, DOCX → archive+xml, картинки → нативно.

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import 'common.dart';

class FileAttachment extends StatefulWidget {
  final matrix.Event event;
  const FileAttachment({super.key, required this.event});

  @override
  State<FileAttachment> createState() => _FileAttachmentState();
}

class _FileAttachmentState extends State<FileAttachment> {
  Uint8List? _bytes;
  bool _expanded = false;
  bool _loading = false;
  String? _error;

  String get _name {
    final fn = widget.event.content['filename'];
    if (fn is String && fn.isNotEmpty) return fn;
    return widget.event.body;
  }

  String get _mime => widget.event.attachmentMimetype;

  String _sizeLabel() {
    final info = widget.event.content['info'];
    final raw = info is Map ? info['size'] : null;
    final s = raw is int ? raw : 0;
    if (s > 1 << 20) return '${(s / (1 << 20)).toStringAsFixed(1)} МБ';
    if (s > 1 << 10) return '${(s / (1 << 10)).toStringAsFixed(0)} КБ';
    return s > 0 ? '$s Б' : '';
  }

  bool get _previewable =>
      _mime.contains('pdf') ||
      _mime.contains('spreadsheet') ||
      _mime.contains('wordprocessing') ||
      _mime.startsWith('image/');

  IconData _icon() {
    if (_mime.contains('pdf')) return Icons.picture_as_pdf;
    if (_mime.contains('spreadsheet')) return Icons.table_chart;
    if (_mime.contains('wordprocessing')) return Icons.description;
    if (_mime.startsWith('image/')) return Icons.image;
    return Icons.insert_drive_file;
  }

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    if (_bytes == null) {
      setState(() => _loading = true);
      try {
        // Скачивает с media repo Synapse и расшифровывает, если комната E2EE.
        final mf = await widget.event.downloadAndDecryptAttachment();
        _bytes = mf.bytes;
        _error = null;
      } catch (e) {
        _error = 'Не удалось загрузить файл';
      }
      _loading = false;
    }
    if (mounted) setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _previewable ? _toggle : null,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon(), size: 30, color: kAccent),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _previewable
                            ? '${_sizeLabel()} · нажмите для просмотра'
                            : _sizeLabel(),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.red))
                : _InlinePreview(bytes: _bytes!, mime: _mime, name: _name),
          ),
      ],
    );
  }
}

class _InlinePreview extends StatelessWidget {
  final Uint8List bytes;
  final String mime;
  final String name;
  const _InlinePreview({
    required this.bytes,
    required this.mime,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final child = () {
      if (mime.startsWith('image/')) {
        return Image.memory(bytes, fit: BoxFit.contain);
      }
      if (mime.contains('pdf')) {
        return PdfViewer.data(bytes, sourceName: name);
      }
      if (mime.contains('spreadsheet')) return _XlsxPreview(bytes: bytes);
      if (mime.contains('wordprocessing')) return _DocxPreview(bytes: bytes);
      return const Text('Предпросмотр недоступен');
    }();

    return Container(
      width: 460,
      height: 400,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _XlsxPreview extends StatelessWidget {
  final Uint8List bytes;
  const _XlsxPreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    try {
      final book = Excel.decodeBytes(bytes);
      final sheet = book.tables[book.tables.keys.first]!;
      final rows = sheet.rows.take(200).toList();
      final cols = sheet.maxColumns.clamp(1, 30);
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 30,
            dataRowMinHeight: 24,
            dataRowMaxHeight: 28,
            columns: List.generate(
              cols,
              (i) =>
                  DataColumn(label: Text(String.fromCharCode(65 + (i % 26)))),
            ),
            rows: rows
                .map(
                  (r) => DataRow(
                    cells: List.generate(
                      cols,
                      (i) => DataCell(
                        Text(
                          i < r.length ? (r[i]?.value?.toString() ?? '') : '',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
    } catch (_) {
      return const Center(child: Text('Не удалось разобрать таблицу'));
    }
  }
}

class _DocxPreview extends StatelessWidget {
  final Uint8List bytes;
  const _DocxPreview({required this.bytes});

  String _extract() {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
    );
    final doc = XmlDocument.parse(
      String.fromCharCodes(entry.content as List<int>),
    );
    final buf = StringBuffer();
    for (final p in doc.findAllElements('w:p')) {
      for (final t in p.findAllElements('w:t')) {
        buf.write(t.innerText);
      }
      buf.writeln();
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final text = _extract();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text.isEmpty ? '(пустой документ)' : text,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      );
    } catch (_) {
      return const Center(child: Text('Не удалось разобрать документ'));
    }
  }
}
