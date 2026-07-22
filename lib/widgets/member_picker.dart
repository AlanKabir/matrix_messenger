// widgets/member_picker.dart — окно выбора сотрудников с галочками.
// Используется при создании группы и при добавлении людей в существующую.
//
// showMemberPicker(...) возвращает список Matrix ID выбранных людей
// или null, если пользователь закрыл окно.

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import 'common.dart';

Future<List<String>?> showMemberPicker(
  BuildContext context,
  matrix.Client client, {
  String title = 'Добавить участников',
  String confirmLabel = 'Добавить',
  // Кого не показывать в списке (уже в группе / это я сам).
  Set<String> exclude = const {},
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _MemberPickerDialog(
      client: client,
      title: title,
      confirmLabel: confirmLabel,
      exclude: exclude,
    ),
  );
}

class _MemberPickerDialog extends StatefulWidget {
  final matrix.Client client;
  final String title;
  final String confirmLabel;
  final Set<String> exclude;

  const _MemberPickerDialog({
    required this.client,
    required this.title,
    required this.confirmLabel,
    required this.exclude,
  });

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<matrix.Profile> _results = [];
  bool _loading = false;
  String? _error;

  // Выбранные: id -> отображаемое имя (имя нужно для «чипов» внизу).
  final Map<String, String> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.searchUserDirectory(
        query.trim(),
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _results = response.results
            .where((p) => !widget.exclude.contains(p.userId))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка поиска: $e';
        _loading = false;
      });
    }
  }

  void _toggle(matrix.Profile p) {
    setState(() {
      if (_selected.containsKey(p.userId)) {
        _selected.remove(p.userId);
      } else {
        _selected[p.userId] = p.displayName ?? p.userId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: T.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- заголовок ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: T.accent,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: T.hint),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // ---- поиск ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _search,
                style: const TextStyle(color: T.text),
                decoration: InputDecoration(
                  hintText: 'Введите фамилию или имя…',
                  hintStyle: const TextStyle(color: T.hint),
                  prefixIcon: const Icon(Icons.search, color: T.hint),
                  filled: true,
                  fillColor: const Color(0xFFF2F5F9),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // ---- выбранные (чипы) ----
            if (_selected.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _selected.entries
                      .map(
                        (e) => Chip(
                          label: Text(
                            e.value,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          backgroundColor: T.selected,
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setState(() => _selected.remove(e.key)),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            // ---- список результатов ----
            Flexible(child: _buildList()),
            const Divider(height: 1, color: T.border),
            // ---- кнопки ----
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? 'Никто не выбран'
                          : 'Выбрано: ${_selected.length}',
                      style: const TextStyle(fontSize: 13, color: T.textSec),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: T.accent),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(_selected.keys.toList()),
                    child: Text(widget.confirmLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(color: T.accent)),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Начните вводить фамилию сотрудника',
            style: TextStyle(color: T.hint),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final p = _results[i];
        final name = p.displayName ?? p.userId;
        final checked = _selected.containsKey(p.userId);
        return Material(
          color: checked ? T.selected : Colors.transparent,
          child: ListTile(
            leading: InitialsAvatar(name: name),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, color: T.text),
            ),
            trailing: Checkbox(
              value: checked,
              activeColor: T.accent,
              onChanged: (_) => _toggle(p),
            ),
            onTap: () => _toggle(p),
          ),
        );
      },
    );
  }
}