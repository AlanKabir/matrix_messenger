import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

class SessionsScreen extends StatefulWidget {
  final matrix.Client client;
  final VoidCallback onLogoutCurrentDevice;

  const SessionsScreen({
    super.key,
    required this.client,
    required this.onLogoutCurrentDevice,
  });

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<matrix.Device>? _devices;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final devices = await widget.client.getDevices();
      devices?.sort((a, b) {
        if (a.deviceId == widget.client.deviceID) return -1;
        if (b.deviceId == widget.client.deviceID) return 1;
        return (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0);
      });
      setState(() {
        _devices = devices;
      });
    } catch (e) {
      setState(() {
        _error = 'Не удалось загрузить сеансы: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _revokeDevice(matrix.Device device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text(
          'Завершить сеанс?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Устройство "${device.displayName ?? device.deviceId}" будет отключено от аккаунта.',
          style: const TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Завершить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      debugPrint(
        "🔍 Пытаюсь удалить устройство с deviceId='${device.deviceId}'",
      );
      await widget.client.deleteDevice(device.deviceId);
      debugPrint("✅ Устройство успешно удалено");
      await _loadDevices();
    } catch (e, s) {
      debugPrint("❌ Полная ошибка при удалении устройства: $e");
      debugPrint("Тип ошибки: ${e.runtimeType}");
      if (e is matrix.MatrixException) {
        debugPrint("errcode: ${e.error}");
        debugPrint("errorMessage: ${e.errorMessage}");
        debugPrint("raw: ${e.raw}");
      }
      debugPrint("Стектрейс: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось завершить сеанс: $e')),
        );
      }
    }
  }

  Future<void> _confirmLogoutCurrentDevice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text(
          'Выйти из аккаунта?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Вы выйдете из текущего сеанса на этом устройстве.',
          style: TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Выйти',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.onLogoutCurrentDevice();
    }
  }

  String _formatLastSeen(int? timestampMs) {
    if (timestampMs == null) return 'Неизвестно';
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин. назад';
    if (diff.inDays < 1) return '${diff.inHours} ч. назад';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161616),
        title: const Text('Сеансы', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            )
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _devices?.length ?? 0,
              separatorBuilder: (context, index) =>
                  const Divider(color: Color(0xFF262626)),
              itemBuilder: (context, index) {
                final device = _devices![index];
                final isCurrent = device.deviceId == widget.client.deviceID;

                return ListTile(
                  leading: Icon(
                    Icons.devices,
                    color: isCurrent
                        ? const Color(0xFF00E676)
                        : const Color(0xFF888888),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.displayName?.isNotEmpty == true
                              ? device.displayName!
                              : device.deviceId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D3823),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Текущий',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    'Последняя активность: ${_formatLastSeen(device.lastSeenTs)}'
                    '${device.lastSeenIp != null ? ' · ${device.lastSeenIp}' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isCurrent ? Icons.logout : Icons.close,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    tooltip: isCurrent
                        ? 'Выйти из текущего сеанса'
                        : 'Завершить сеанс',
                    onPressed: () {
                      if (isCurrent) {
                        _confirmLogoutCurrentDevice();
                      } else {
                        _revokeDevice(device);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
