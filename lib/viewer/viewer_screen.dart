import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../l10n/locale_provider.dart';
import '../shared/notif_tile.dart';

enum _DeviceState { awaitingConsent, accepted, rejected }

class _MonitoredDevice {
  final String uid;
  final String email;
  _DeviceState state;
  StreamSubscription<DatabaseEvent>? requestSub;
  StreamSubscription<DatabaseEvent>? countSub;
  int newCount = 0;

  _MonitoredDevice({
    required this.uid,
    required this.email,
    required this.state,
  });
}

class ViewerScreen extends StatefulWidget {
  final bool isActive;
  final void Function(int) onNewCount;

  const ViewerScreen({
    super.key,
    required this.isActive,
    required this.onNewCount,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Whether the user's own device is being monitored
  bool _selfMonitored = true;

  // Remote devices being monitored
  final List<_MonitoredDevice> _devices = [];

  late String _myUid;

  StreamSubscription<DatabaseEvent>? _countSub;
  int _selfNewCount = 0;
  DateTime _lastSeenTime = DateTime.now();
  bool _soundEnabled = true;
  final AudioPlayer _audioPlayer = AudioPlayer();

  int get _totalNewCount =>
      _selfNewCount + _devices.fold(0, (sum, d) => sum + d.newCount);

  void _reportCount() => widget.onNewCount(_totalNewCount);

  int get _totalDevices => (_selfMonitored ? 1 : 0) + _devices.length;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser!.uid;
    _tabController = TabController(length: 1, vsync: this);
    _loadDevicesFromPrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _soundEnabled = LocaleNotifier.of(context).viewerSound;
  }

  @override
  void didUpdateWidget(ViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _lastSeenTime = DateTime.now();
      _selfNewCount = 0;
      for (final d in _devices) {
        d.newCount = 0;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onNewCount(0);
      });
    }
  }

  int _countNewSince(Map data) => data.values.where((v) {
        try {
          return DateTime.parse((v as Map)['receivedAt'] as String? ?? '')
              .isAfter(_lastSeenTime);
        } catch (_) {
          return false;
        }
      }).length;

  void _startCountListening() {
    _countSub?.cancel();
    _countSub = FirebaseDatabase.instance
        .ref('users/$_myUid/notifications')
        .orderByChild('receivedAt')
        .limitToLast(50)
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (widget.isActive) {
        _selfNewCount = 0;
        _reportCount();
        return;
      }
      final data = event.snapshot.value;
      final prev = _totalNewCount;
      _selfNewCount = data == null ? 0 : _countNewSince(data as Map);
      if (_soundEnabled && _totalNewCount > prev) {
        _audioPlayer.play(AssetSource('sounds/notification.wav'));
      }
      _reportCount();
    });
  }

  void _startDeviceCountListening(_MonitoredDevice device) {
    device.countSub?.cancel();
    device.countSub = FirebaseDatabase.instance
        .ref('users/${device.uid}/notifications')
        .orderByChild('receivedAt')
        .limitToLast(50)
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (widget.isActive) {
        device.newCount = 0;
        _reportCount();
        return;
      }
      final data = event.snapshot.value;
      final prev = _totalNewCount;
      device.newCount = data == null ? 0 : _countNewSince(data as Map);
      if (_soundEnabled && _totalNewCount > prev) {
        _audioPlayer.play(AssetSource('sounds/notification.wav'));
      }
      _reportCount();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _countSub?.cancel();
    for (final d in _devices) {
      d.requestSub?.cancel();
      d.countSub?.cancel();
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadDevicesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrate old single-device format
    final oldEmail = prefs.getString('viewerTargetEmail');
    final oldUid = prefs.getString('viewerTargetUid');
    if (oldEmail != null && oldUid != null) {
      await prefs.remove('viewerTargetEmail');
      await prefs.remove('viewerTargetUid');
      if (oldUid != _myUid) {
        await prefs.setString(
            'viewerDevices', jsonEncode([{'uid': oldUid, 'email': oldEmail}]));
      }
    }

    _selfMonitored = prefs.getBool('viewerSelfMonitored') ?? true;
    if (_selfMonitored) _startCountListening();

    final raw = prefs.getString('viewerDevices');
    if (raw != null && mounted) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final item in list) {
        final uid = item['uid'] as String;
        final email = item['email'] as String;

        final snapshot = await FirebaseDatabase.instance
            .ref('users/$uid/incoming_requests/$_myUid')
            .get();

        if (!mounted) return;
        if (!snapshot.exists) continue;

        final status = (snapshot.value as Map)['status'] as String?;
        if (status == 'rejected') continue;

        final device = _MonitoredDevice(
          uid: uid,
          email: email,
          state: status == 'accepted'
              ? _DeviceState.accepted
              : _DeviceState.awaitingConsent,
        );
        _devices.add(device);
        _listenRequestStatus(device);
        if (device.state == _DeviceState.accepted) {
          _startDeviceCountListening(device);
        }
      }
    }

    if (!mounted) return;
    await _saveDevicesToPrefs();
    await _saveSelfToPrefs(_selfMonitored);

    if (_totalDevices > 0) {
      setState(() => _rebuildTabController());
    } else {
      setState(() {});
    }
  }

  Future<void> _saveDevicesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_devices.isEmpty) {
      await prefs.remove('viewerDevices');
    } else {
      await prefs.setString(
        'viewerDevices',
        jsonEncode(
            _devices.map((d) => {'uid': d.uid, 'email': d.email}).toList()),
      );
    }
  }

  Future<void> _saveSelfToPrefs(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('viewerSelfMonitored', value);
  }

  // ── Tab controller ─────────────────────────────────────────────────────────

  /// Rebuilds the tab controller. Delays disposal of the old one to avoid
  /// use-after-dispose when the TabBar's InkWell fires after the rebuild.
  void _rebuildTabController({int? targetIndex}) {
    final total = _totalDevices;
    assert(total > 0);
    final old = _tabController;
    final current = old.index.clamp(0, total - 1);
    _tabController = TabController(
      length: total,
      vsync: this,
      initialIndex: (targetIndex ?? current).clamp(0, total - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  // ── Device management ──────────────────────────────────────────────────────

  void _addSelf() {
    setState(() {
      _selfMonitored = true;
      if (_totalDevices > 1) {
        _rebuildTabController(targetIndex: 0);
      } else {
        _rebuildTabController(targetIndex: 0);
      }
    });
    _startCountListening();
    _saveSelfToPrefs(true);
  }

  void _removeSelf() {
    _countSub?.cancel();
    setState(() {
      _selfMonitored = false;
      if (_devices.isNotEmpty) _rebuildTabController();
      // else: totalDevices = 0 → empty state, no controller rebuild
    });
    _saveSelfToPrefs(false);
  }

  void _addDevice(_MonitoredDevice device) {
    _listenRequestStatus(device);
    if (device.state == _DeviceState.accepted) {
      _startDeviceCountListening(device);
    }
    setState(() {
      _devices.add(device);
      final newIndex = (_selfMonitored ? 1 : 0) + _devices.length - 1;
      _rebuildTabController(targetIndex: newIndex);
    });
    _saveDevicesToPrefs();
  }

  void _removeDevice(_MonitoredDevice device) {
    device.requestSub?.cancel();
    device.countSub?.cancel();
    device.newCount = 0;
    setState(() {
      _devices.remove(device);
      if (_totalDevices > 0) _rebuildTabController();
      // else: empty state
    });
    _reportCount();
    _saveDevicesToPrefs();
  }

  void _listenRequestStatus(_MonitoredDevice device) {
    device.requestSub?.cancel();
    device.requestSub = FirebaseDatabase.instance
        .ref('users/${device.uid}/incoming_requests/$_myUid/status')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final status = event.snapshot.value as String?;
      // null = request node was deleted by owner → treat as removed
      if (status == null || status == 'rejected') {
        device.requestSub?.cancel();
        _removeDevice(device);
        return;
      }
      final wasAccepted = device.state == _DeviceState.accepted;
      setState(() {
        device.state = switch (status) {
          'accepted' => _DeviceState.accepted,
          _ => _DeviceState.awaitingConsent,
        };
      });
      if (status == 'accepted' && !wasAccepted) {
        _startDeviceCountListening(device);
      } else if (status != 'accepted' && wasAccepted) {
        device.countSub?.cancel();
        device.newCount = 0;
        _reportCount();
      }
    });
  }

  void _showAddDeviceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddDeviceSheet(
        myUid: _myUid,
        existingUids: _devices.map((d) => d.uid).toSet(),
        selfAlreadyMonitored: _selfMonitored,
        onDeviceAdded: (device) {
          Navigator.pop(ctx);
          _addDevice(device);
        },
        onSelfAdded: () {
          Navigator.pop(ctx);
          _addSelf();
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      body: _totalDevices == 0
          ? _buildEmptyState()
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    if (_selfMonitored)
                      _CloseableTab(
                          label: s.thisDevice, onClose: _removeSelf),
                    ..._devices.map((d) => _CloseableTab(
                          label: d.email,
                          onClose: () => _removeDevice(d),
                        )),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      if (_selfMonitored)
                        _DeviceNotificationsView(uid: _myUid, onRemove: null),
                      ..._devices.map(_buildDeviceBody),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDeviceSheet,
        tooltip: s.addDevice,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices_other, size: 64, color: colors.outline),
          const SizedBox(height: 16),
          Text(s.noMonitoredDevices,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colors.outline)),
          const SizedBox(height: 8),
          Text(s.tapPlusToAdd,
              style: TextStyle(color: colors.outline, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDeviceBody(_MonitoredDevice device) {
    return switch (device.state) {
      _DeviceState.accepted => _DeviceNotificationsView(
          uid: device.uid,
          onRemove: null,
        ),
      _DeviceState.awaitingConsent => _buildAwaitingView(device),
      _DeviceState.rejected => _buildRejectedView(device),
    };
  }

  Widget _buildAwaitingView(_MonitoredDevice device) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 64, color: colors.primary),
            const SizedBox(height: 24),
            Text(
              s.requestSent,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              s.awaitingConsent(device.email),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline),
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedView(_MonitoredDevice device) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 64, color: colors.error),
            const SizedBox(height: 24),
            Text(
              s.requestRejectedTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              s.requestRejectedBy(device.email),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Closeable tab label ────────────────────────────────────────────────────────

class _CloseableTab extends StatelessWidget {
  final String label;
  final VoidCallback onClose;

  const _CloseableTab({required this.label, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, size: 15),
          ),
        ],
      ),
    );
  }
}

// ── Notifications list for a single device ─────────────────────────────────────

class _DeviceNotificationsView extends StatefulWidget {
  final String uid;
  final VoidCallback? onRemove;

  const _DeviceNotificationsView({required this.uid, required this.onRemove});

  @override
  State<_DeviceNotificationsView> createState() =>
      _DeviceNotificationsViewState();
}

class _DeviceNotificationsViewState extends State<_DeviceNotificationsView> {
  Stream<DatabaseEvent>? _stream;
  bool _retryScheduled = false;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
  }

  Stream<DatabaseEvent> _buildStream() => FirebaseDatabase.instance
      .ref('users/${widget.uid}/notifications')
      .orderByChild('receivedAt')
      .limitToLast(50)
      .onValue;

  void _subscribe() {
    _retryScheduled = false;
    setState(() {
      _stream = _buildStream();
    });
  }

  void _scheduleRetry() {
    if (_retryScheduled) return;
    _retryScheduled = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _subscribe();
    });
  }

  Future<void> _deleteOne(BuildContext context, String key) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseDatabase.instance
          .ref('users/${widget.uid}/notifications/$key')
          .remove();
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    }
  }

  Future<void> _deleteAll() =>
      FirebaseDatabase.instance.ref('users/${widget.uid}/notifications').remove();

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteAllConfirmTitle),
        content: Text(s.deleteAllConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(s.deleteAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _deleteAll();
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;

    return StreamBuilder<DatabaseEvent>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          _scheduleRetry();
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error.toString(),
                  style: TextStyle(color: colors.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _subscribe,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data?.snapshot.value;
        if (data == null) {
          return Center(
            child: Text(
              s.noNotificationsYet,
              style: TextStyle(color: colors.outline),
            ),
          );
        }

        final entries = (data as Map)
            .entries
            .map((e) => {
                  '_fbKey': e.key as String,
                  ...Map<String, dynamic>.from(e.value as Map),
                })
            .toList()
          ..sort((a, b) => (b['receivedAt'] as String? ?? '')
              .compareTo(a['receivedAt'] as String? ?? ''));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Text('${entries.length}',
                      style: TextStyle(color: colors.outline, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.delete_sweep, color: colors.error),
                    tooltip: s.deleteAll,
                    onPressed: () => _confirmDeleteAll(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  final key = entry['_fbKey'] as String;
                  return Dismissible(
                    key: ValueKey(key),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.delete, color: colors.error),
                    ),
                    onDismissed: (_) => _deleteOne(context, key),
                    child: NotifTile(data: entry),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Bottom sheet: add a new device ─────────────────────────────────────────────

enum _AddState { input, searching }

class _AddDeviceSheet extends StatefulWidget {
  final String myUid;
  final Set<String> existingUids;
  final bool selfAlreadyMonitored;
  final void Function(_MonitoredDevice device) onDeviceAdded;
  final VoidCallback onSelfAdded;

  const _AddDeviceSheet({
    required this.myUid,
    required this.existingUids,
    required this.selfAlreadyMonitored,
    required this.onDeviceAdded,
    required this.onSelfAdded,
  });

  @override
  State<_AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends State<_AddDeviceSheet> {
  final _emailController = TextEditingController();
  _AddState _state = _AddState.input;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _sanitize(String email) =>
      email.trim().toLowerCase().replaceAll('.', ',');

  Future<void> _submit() async {
    final typedEmail = _emailController.text.trim().toLowerCase();
    if (typedEmail.isEmpty) return;

    setState(() {
      _state = _AddState.searching;
      _errorText = null;
    });

    final s = S.of(context);

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('user_lookup/${_sanitize(typedEmail)}')
          .get();

      if (!mounted) return;

      if (!snapshot.exists || snapshot.value == null) {
        setState(() {
          _state = _AddState.input;
          _errorText = s.userNotFound;
        });
        return;
      }

      final targetUid = snapshot.value as String;

      // Own device: add back without a request flow
      if (targetUid == widget.myUid) {
        if (widget.selfAlreadyMonitored) {
          setState(() {
            _state = _AddState.input;
            _errorText = s.alreadyMonitoring;
          });
        } else {
          widget.onSelfAdded();
        }
        return;
      }

      if (widget.existingUids.contains(targetUid)) {
        setState(() {
          _state = _AddState.input;
          _errorText = s.alreadyMonitoring;
        });
        return;
      }

      final myEmail = FirebaseAuth.instance.currentUser!.email ?? '';

      final existing = await FirebaseDatabase.instance
          .ref('users/$targetUid/incoming_requests/${widget.myUid}')
          .get();

      if (!mounted) return;

      _DeviceState deviceState;
      if (existing.exists) {
        final status = (existing.value as Map)['status'] as String?;
        if (status == 'accepted') {
          deviceState = _DeviceState.accepted;
        } else {
          await FirebaseDatabase.instance
              .ref('users/$targetUid/incoming_requests/${widget.myUid}')
              .set({'email': myEmail, 'status': 'pending'});
          deviceState = _DeviceState.awaitingConsent;
        }
      } else {
        await FirebaseDatabase.instance
            .ref('users/$targetUid/incoming_requests/${widget.myUid}')
            .set({'email': myEmail, 'status': 'pending'});
        deviceState = _DeviceState.awaitingConsent;
      }

      if (!mounted) return;

      widget.onDeviceAdded(_MonitoredDevice(
        uid: targetUid,
        email: typedEmail,
        state: deviceState,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _AddState.input;
        _errorText = s.requestFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final searching = _state == _AddState.searching;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.addDevice,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            s.viewerSubtitle,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.search,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: s.userEmail,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: searching ? null : _submit,
            icon: searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
            label: Text(s.sendRequest),
          ),
        ],
      ),
    );
  }
}
