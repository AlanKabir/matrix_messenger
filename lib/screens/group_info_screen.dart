// screens/group_info_screen.dart — экран «Информация о группе».
// Возможности:
//   • фото и название группы (меняют администраторы);
//   • список участников с ролями и фотографиями;
//   • назначить/снять администратора;
//   • удалить участника из группы;
//   • переключатель «добавлять участников могут только администраторы»;
//   • выйти из группы.
//
// Права: менять роли и настройки может тот, у кого уровень >= 50
// (в Matrix это «модератор/админ»). У создателя группы обычно 100.
//
// ВАЖНО про состав группы: Synapse присылает участников ЛЕНИВО — только тех,
// кто недавно писал. Поэтому при открытии экрана состав запрашивается
// с сервера принудительно (_refreshMembers).

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../app_theme.dart';
import '../widgets/common.dart';
import '../widgets/member_picker.dart';

// Максимальный размер фото группы.
const int _maxAvatarBytes = 5 * 1024 * 1024;

class GroupInfoScreen extends StatefulWidget {
  final matrix.Room room;
  const GroupInfoScreen({super.key, required this.room});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  matrix.Room get _room => widget.room;

  bool _busy = false;
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _refreshMembers();
  }

  // Полный состав группы с сервера (обходит ленивую загрузку).
  Future<void> _refreshMembers() async {
    try {
      await _room.postLoad();
    } catch (_) {}
    try {
      await _room.requestParticipants();
    } catch (_) {}
    if (mounted) setState(() => _loadingMembers = false);
  }

  // Мой уровень прав в комнате. 100 — создатель, 50 — админ/модератор, 0 — обычный.
  int get _myPower => _powerOfId(_room.client.userID ?? '');
  bool get _canManage => _myPower >= 50;

  // Требуется ли уровень 50+, чтобы приглашать (т.е. «только админы»).
  bool get _inviteAdminsOnly {
    final content = _room.getState(matrix.EventTypes.RoomPowerLevels)?.content;
    final invite = content?['invite'];
    if (invite is num) return invite >= 50;
    return false;
  }

  // Уровень прав по Matrix ID, читаем прямо из состояния комнаты —
  // так не зависим от типов, которые менялись между версиями SDK.
  int _powerOfId(String id) {
    final content = _room.getState(matrix.EventTypes.RoomPowerLevels)?.content;
    final users = content?['users'];
    if (users is Map && users[id] is num) return (users[id] as num).toInt();
    final def = content?['users_default'];
    if (def is num) return def.toInt();
    return 0;
  }

  int _powerOf(matrix.User u) => _powerOfId(u.id);

  String _roleLabel(int power) {
    if (power >= 100) return 'Создатель';
    if (power >= 50) return 'Администратор';
    return 'Участник';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- Фото группы ----------------------------------------------------------

  Future<void> _pickGroupAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Фотография группы',
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.bytes!.length > _maxAvatarBytes) {
      _snack('Фото больше 5 МБ — выберите файл поменьше');
      return;
    }
    setState(() => _busy = true);
    try {
      final uri = await _room.client.uploadContent(f.bytes!, filename: f.name);
      await _room.client.setRoomStateWithKey(_room.id, 'm.room.avatar', '', {
        'url': uri.toString(),
      });
      _snack('Фотография группы обновлена');
    } catch (e) {
      _snack('Не удалось загрузить фото: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Название группы ------------------------------------------------------

  Future<void> _renameGroup() async {
    final ctrl = TextEditingController(text: _room.getLocalizedDisplayname());
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Новое название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await _room.client.setRoomStateWithKey(_room.id, 'm.room.name', '', {
        'name': newName,
      });
      _snack('Название изменено');
    } catch (e) {
      _snack('Не удалось изменить название: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Переключатель «приглашать могут только админы».
  Future<void> _setInviteAdminsOnly(bool adminsOnly) async {
    setState(() => _busy = true);
    try {
      final current =
          _room.getState(matrix.EventTypes.RoomPowerLevels)?.content ??
          <String, Object?>{};
      final content = Map<String, dynamic>.from(current);
      content['invite'] = adminsOnly ? 50 : 0;
      await _room.client.setRoomStateWithKey(
        _room.id,
        matrix.EventTypes.RoomPowerLevels,
        '',
        content,
      );
      _snack(
        adminsOnly
            ? 'Теперь приглашать могут только администраторы'
            : 'Теперь приглашать могут все участники',
      );
    } catch (e) {
      _snack('Не удалось изменить настройку: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Назначить администратором / снять права.
  Future<void> _setPower(matrix.User user, int power) async {
    setState(() => _busy = true);
    try {
      await _room.setPower(user.id, power);
      _snack(
        power >= 50
            ? '${user.calcDisplayname()} — теперь администратор'
            : 'Права администратора сняты',
      );
      await _refreshMembers();
    } catch (e) {
      _snack('Не удалось изменить права: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Удалить участника из группы.
  Future<void> _kick(matrix.User user) async {
    final name = user.calcDisplayname();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить из группы?'),
        content: Text('$name будет удалён из группы.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _room.kick(user.id);
      _snack('$name удалён из группы');
      await _refreshMembers();
    } catch (e) {
      _snack('Не удалось удалить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Добавить участников.
  Future<void> _addMembers() async {
    final already = _room.getParticipants().map((u) => u.id).toSet();
    final members = await showMemberPicker(
      context,
      _room.client,
      title: 'Добавить в «${_room.getLocalizedDisplayname()}»',
      confirmLabel: 'Добавить',
      exclude: already,
    );
    if (members == null || members.isEmpty || !mounted) return;
    setState(() => _busy = true);
    int ok = 0;
    int fail = 0;
    for (final id in members) {
      try {
        await _room.invite(id);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    _snack(fail == 0 ? 'Приглашено: $ok' : 'Приглашено: $ok, ошибок: $fail');
    await _refreshMembers();
    if (mounted) setState(() => _busy = false);
  }

  // Выйти из группы.
  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content: const Text(
          'Вы перестанете получать сообщения этой группы. '
          'Вернуться можно будет только по новому приглашению.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _room.leave();
      if (mounted) Navigator.of(context).pop(true); // true = вышли
    } catch (e) {
      _snack('Не удалось выйти: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _room.getLocalizedDisplayname();
    final members = _room.getParticipants()
      ..sort((a, b) => _powerOf(b).compareTo(_powerOf(a)));

    return Scaffold(
      backgroundColor: T.panel,
      appBar: AppBar(
        title: const Text('О группе'),
        backgroundColor: T.accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Обновить состав',
            icon: const Icon(Icons.refresh),
            onPressed: _loadingMembers
                ? null
                : () {
                    setState(() => _loadingMembers = true);
                    _refreshMembers();
                  },
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              // ---- шапка группы: фото + название ----
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: T.panelAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: T.border),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        InitialsAvatar(
                          name: title,
                          group: true,
                          radius: 32,
                          mxcUrl: _room.avatar,
                          client: _room.client,
                        ),
                        // Кнопка смены фото — только для администраторов.
                        if (_canManage)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: T.gold,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _busy ? null : _pickGroupAvatar,
                                child: const Padding(
                                  padding: EdgeInsets.all(5),
                                  child: Icon(
                                    Icons.photo_camera,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: T.text,
                                  ),
                                ),
                              ),
                              if (_canManage)
                                IconButton(
                                  tooltip: 'Переименовать группу',
                                  icon: const Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: T.hint,
                                  ),
                                  onPressed: _busy ? null : _renameGroup,
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _loadingMembers
                                ? 'Загрузка состава…'
                                : '${members.length} участников',
                            style: const TextStyle(
                              fontSize: 13,
                              color: T.textSec,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ---- настройка прав ----
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: T.panelAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: T.border),
                ),
                child: SwitchListTile(
                  value: _inviteAdminsOnly,
                  activeThumbColor: T.accent,
                  title: const Text(
                    'Добавлять участников могут только администраторы',
                    style: TextStyle(fontSize: 14, color: T.text),
                  ),
                  subtitle: Text(
                    _canManage
                        ? 'Обычные участники не смогут приглашать людей'
                        : 'Менять может только администратор',
                    style: const TextStyle(fontSize: 12, color: T.hint),
                  ),
                  onChanged: (_canManage && !_busy)
                      ? (v) => _setInviteAdminsOnly(v)
                      : null,
                ),
              ),

              // ---- участники ----
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Участники',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: T.textSec,
                        ),
                      ),
                    ),
                    if (_canManage || !_inviteAdminsOnly)
                      TextButton.icon(
                        onPressed: _busy ? null : _addMembers,
                        icon: const Icon(Icons.person_add_alt, size: 18),
                        label: const Text('Добавить'),
                        style: TextButton.styleFrom(foregroundColor: T.accent),
                      ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: T.panelAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: T.border),
                ),
                child: _loadingMembers && members.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: T.accent,
                            ),
                          ),
                        ),
                      )
                    : Column(children: members.map(_memberTile).toList()),
              ),

              // ---- выход ----
              const SizedBox(height: 24),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: T.panelAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: T.border),
                ),
                child: ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Выйти из группы',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: _busy ? null : _leave,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
          if (_busy || _loadingMembers)
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

  Widget _memberTile(matrix.User user) {
    final name = user.calcDisplayname();
    final power = _powerOf(user);
    final isMe = user.id == _room.client.userID;
    final isInvited = user.membership == matrix.Membership.invite;
    // Управлять можно только теми, чей уровень НИЖЕ моего, и не собой.
    final canManageThis = _canManage && !isMe && power < _myPower;

    return ListTile(
      leading: InitialsAvatar(
        name: name,
        mxcUrl: user.avatarUrl,
        client: _room.client,
      ),
      title: Text(
        name + (isMe ? ' (вы)' : ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, color: T.text),
      ),
      subtitle: Text(
        isInvited ? 'Приглашён — ещё не принял' : _roleLabel(power),
        style: TextStyle(
          fontSize: 12,
          color: power >= 50 ? T.accent : T.hint,
          fontWeight: power >= 50 ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: canManageThis
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: T.hint, size: 20),
              onSelected: (v) {
                switch (v) {
                  case 'promote':
                    _setPower(user, 50);
                    break;
                  case 'demote':
                    _setPower(user, 0);
                    break;
                  case 'kick':
                    _kick(user);
                    break;
                }
              },
              itemBuilder: (_) => [
                if (power < 50)
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('Назначить администратором'),
                  ),
                if (power >= 50)
                  const PopupMenuItem(
                    value: 'demote',
                    child: Text('Снять права администратора'),
                  ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text(
                    'Удалить из группы',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}
