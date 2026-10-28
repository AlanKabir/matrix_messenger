// screens/admin_limits_screen.dart — «Лимиты отправки файлов» (только админ).
//
// • Ползунок «По умолчанию для всех».
// • Список сотрудников с персональным лимитом: добавить, изменить, убрать.
// Каждое изменение сразу сохраняется на сервере и через несколько секунд
// действует у сотрудника — переустанавливать ничего не нужно.

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../services/upload_limits.dart';
import '../widgets/common.dart';
import '../widgets/member_picker.dart';

class AdminLimitsScreen extends StatefulWidget {
  final matrix.Client client;
  const AdminLimitsScreen({super.key, required this.client});

  @override
  State<AdminLimitsScreen> createState() => _AdminLimitsScreenState();
}

class _AdminLimitsScreenState extends State<AdminLimitsScreen> {
  final UploadLimits _limits = UploadLimits.instance;

  late int _defaultMb;
  late Map<String, int> _users;
  bool _saving = false;
  String? _error;

  // Кэш имён сотрудников: Matrix ID → ФИО (и фото).
  final Map<String, Future<matrix.Profile?>> _profiles = {};

  @override
  void initState() {
    super.initState();
    _defaultMb = _limits.defaultMb;
    _users = Map.of(_limits.users);
    _prepareRoom();
  }

  // Создаём служебную комнату при первом открытии экрана.
  Future<void> _prepareRoom() async {
    if (_limits.hasSettingsRoom) return;
    setState(() => _saving = true);
    try {
      await _limits.ensureSettingsRoom();
      if (!mounted) return;
      setState(() {
        _defaultMb = _limits.defaultMb;
        _users = Map.of(_limits.users);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось подготовить настройки: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<matrix.Profile?> _profile(String userId) => _profiles.putIfAbsent(
    userId,
    () => widget.client
        .getProfileFromUserId(userId)
        .then<matrix.Profile?>((p) => p)
        .catchError((_) => null),
  );

  // Ползунок двигается шагом 5 МБ от minLimitMb до потолка сервера.
  int get _min => UploadLimits.minLimitMb;
  int get _max => _limits.serverCapMb < _min ? _min : _limits.serverCapMb;
  int? get _divisions {
    final d = ((_max - _min) / 5).round();
    return d > 0 ? d : null;
  }

  int _clamp(int v) => v < _min ? _min : (v > _max ? _max : v);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _limits.save(defaultMb: _defaultMb, users: _users);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сохранено. У сотрудников — через несколько секунд'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось сохранить: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Диалог с ползунком для одного или нескольких сотрудников.
  Future<int?> _pickValue(String title, int initial) {
    var value = _clamp(initial);
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value МБ',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: T.accent,
                  ),
                ),
                Slider(
                  value: value.toDouble(),
                  min: _min.toDouble(),
                  max: _max.toDouble(),
                  divisions: _divisions,
                  activeColor: T.accent,
                  label: '$value МБ',
                  onChanged: (v) => setLocal(() => value = v.round()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$_min МБ', style: const TextStyle(color: T.textSec)),
                    Text('$_max МБ', style: const TextStyle(color: T.textSec)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: T.accent),
              onPressed: () => Navigator.pop(ctx, value),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPeople() async {
    final ids = await showMemberPicker(
      context,
      widget.client,
      title: 'Кому изменить лимит',
      confirmLabel: 'Далее',
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final value = await _pickValue(
      ids.length == 1
          ? 'Лимит для сотрудника'
          : 'Лимит для ${ids.length} сотрудников',
      _defaultMb + 10,
    );
    if (value == null) return;
    setState(() {
      for (final id in ids) {
        _users[id] = value;
      }
    });
    await _save();
  }

  Future<void> _editPerson(String userId, String name) async {
    final value = await _pickValue(name, _users[userId] ?? _defaultMb);
    if (value == null) return;
    setState(() => _users[userId] = value);
    await _save();
  }

  Future<void> _removePerson(String userId) async {
    setState(() => _users.remove(userId));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _users.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      backgroundColor: T.panel,
      appBar: AppBar(
        title: const Text('Лимиты отправки файлов'),
        backgroundColor: T.accent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- пояснение ---
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Text(
                  'Потолок сервера: ${_limits.serverCapMb} МБ — больше не '
                  'разрешить никому. Изменения действуют у сотрудников через '
                  'несколько секунд, переустанавливать приложение не нужно.',
                  style: const TextStyle(fontSize: 13, color: T.text),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),

              // --- по умолчанию для всех ---
              const SizedBox(height: 20),
              _card([
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_outlined, color: T.accent),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'По умолчанию для всех',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: T.text,
                          ),
                        ),
                      ),
                      Text(
                        '$_defaultMb МБ',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: T.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Slider(
                    value: _clamp(_defaultMb).toDouble(),
                    min: _min.toDouble(),
                    max: _max.toDouble(),
                    divisions: _divisions,
                    activeColor: T.accent,
                    label: '$_defaultMb МБ',
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _defaultMb = v.round()),
                    // Сохраняем, когда отпустили ползунок, а не на каждый пиксель.
                    onChangeEnd: (_) => _save(),
                  ),
                ),
              ]),

              // --- персональные лимиты ---
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Персональные лимиты',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: T.steel,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : _addPeople,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Добавить сотрудников'),
                    style: TextButton.styleFrom(foregroundColor: T.accent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Пока у всех лимит по умолчанию',
                      style: TextStyle(color: T.textSec),
                    ),
                  ),
                )
              else
                _card([
                  for (final e in entries)
                    FutureBuilder<matrix.Profile?>(
                      future: _profile(e.key),
                      builder: (_, snap) {
                        final name = snap.data?.displayName ?? e.key;
                        final capped = e.value > _limits.serverCapMb;
                        return ListTile(
                          leading: InitialsAvatar(
                            name: name,
                            radius: 18,
                            mxcUrl: snap.data?.avatarUrl,
                            client: widget.client,
                          ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: T.text),
                          ),
                          subtitle: Text(
                            capped
                                ? '${e.value} МБ (сервер ограничит до ${_limits.serverCapMb} МБ)'
                                : '${e.value} МБ',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: capped ? Colors.orange : T.textSec,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Вернуть лимит по умолчанию',
                            icon: const Icon(Icons.close, color: T.hint),
                            onPressed: _saving
                                ? null
                                : () => _removePerson(e.key),
                          ),
                          onTap: _saving
                              ? null
                              : () => _editPerson(e.key, name),
                        );
                      },
                    ),
                ]),
            ],
          ),
          if (_saving)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2, color: T.accent),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: T.panelAlt,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: T.border),
    ),
    child: Column(children: children),
  );
}
