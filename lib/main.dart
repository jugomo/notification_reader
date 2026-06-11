import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'auth/auth_screen.dart';
import 'firebase_options.dart';
import 'l10n/app_strings.dart';
import 'l10n/locale_provider.dart';
import 'requests/requests_screen.dart';
import 'settings/settings_screen.dart';
import 'shared/encryption_util.dart';
import 'viewer/viewer_screen.dart';

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

// Guarda una notificación bajo users/{uid}/notifications/ con los campos
// appName, title y body encriptados con AES-256-GCM.
Future<void> _saveNotification(Map<String, dynamic> data) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final encData = Map<String, dynamic>.from(data);
  for (final field in ['appName', 'title', 'body']) {
    final value = encData[field];
    if (value is String && value.isNotEmpty) {
      encData[field] = EncryptionUtil.encrypt(value);
    }
  }
  await FirebaseDatabase.instance.ref('users/$uid/notifications').push().set(encData);
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await EncryptionUtil.init();
  await _saveNotification({
    'source': 'fcm',
    'title': message.notification?.title ?? '',
    'body': message.notification?.body ?? '',
    'data': message.data,
    'receivedAt': DateTime.now().toUtc().toIso8601String(),
    'messageId': message.messageId,
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await EncryptionUtil.init();
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (_) {}
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  FirebaseMessaging.instance.getToken().then((token) => debugPrint('FCM Token: $token')).catchError((_) {});
  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    ),
  );
  runApp(const LocaleProvider(child: NotificationReaderApp()));
}

class NotificationReaderApp extends StatelessWidget {
  const NotificationReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = LocaleNotifier.of(context);
    return MaterialApp(
      title: 'Notification Reader',
      locale: notifier.locale,
      themeMode: notifier.themeMode,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = authSnapshot.data;
          if (user == null) return const AuthScreen();

          return StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance
                .ref('users/${user.uid}/profile/admin_approved')
                .onValue,
            builder: (context, approvedSnapshot) {
              if (approvedSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final approved = approvedSnapshot.data?.snapshot.value;
              // null = usuario antiguo sin el campo → acceso normal
              if (approved == null || approved == true) return const HomePage();
              return const _PendingApprovalScreen();
            },
          );
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _serviceChannel = MethodChannel('com.jugomo.notification_reader/service');
  static const _notifChannel = EventChannel('com.jugomo.notification_reader/notifications');
  static const _badgeChannel = MethodChannel('com.jugomo.notification_reader/badge');

  bool _hasPermission = false;
  bool _serviceRunning = false;
  int _currentTab = 0;
  int _viewerNewCount = 0;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saveUserProfile();
    _sendEncryptionKey();
    _checkPermission();
    _initFcm();
    _initSystemNotificationListener();
    if (kIsWeb) _loadSelfDecryptionKey();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && _serviceRunning) _stopService();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _fcmSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  // Persiste email del usuario para que otros puedan buscarlo
  Future<void> _saveUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    // Make EncryptionUtil aware of this uid so decryptForUid works correctly.
    EncryptionUtil.setOwnUid(user.uid);

    final sanitizedEmail = user.email!.toLowerCase().replaceAll('.', ',');
    final db = FirebaseDatabase.instance;
    final profileRef = db.ref('users/${user.uid}/profile');

    final updates = <String, dynamic>{
      'email': user.email,
      'uid': user.uid,
      // Publish RSA public key so authorised viewers can receive our AES key.
      if (EncryptionUtil.rsaPublicKeyBase64 != null)
        'publicKey': EncryptionUtil.rsaPublicKeyBase64!,
    };

    // Si el campo no existe es un usuario anterior a esta funcionalidad → aprobado por defecto
    final approvedSnap = await profileRef.child('admin_approved').get();
    if (!approvedSnap.exists) updates['admin_approved'] = true;

    await Future.wait([
      profileRef.update(updates),
      db.ref('user_lookup/$sanitizedEmail').set(user.uid),
    ]);
  }

  // Escucha notificaciones del sistema vía EventChannel.
  // La persistencia en Firebase la hace NotificationReaderService.kt directamente,
  // por lo que aquí no hace falta escribir nada (evita duplicados cuando la app está viva).
  void _initSystemNotificationListener() {
    if (!_isAndroid) return;
    _notifChannel.receiveBroadcastStream().listen((_) {});
  }

  Future<void> _initFcm() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground
    _fcmSub = FirebaseMessaging.onMessage.listen((message) async {
      await _saveNotification({
        'source': 'fcm',
        'title': message.notification?.title ?? '',
        'body': message.notification?.body ?? '',
        'data': message.data,
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
        'messageId': message.messageId,
      });
      _showSnackbar(message.notification?.title, message.notification?.body);
    });

    // Abierta desde background (ya guardada por el background handler)
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});

    // Abierta desde terminada (ya guardada por el background handler)
    await messaging.getInitialMessage();
  }

  void _showSnackbar(String? title, String? body) {
    if (!mounted) return;
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${title ?? s.noTitle}\n${body ?? ''}'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  bool get _isMonitoringSupported => _isAndroid || _isMacOS;

  Future<void> _sendEncryptionKey() async {
    if (!_isAndroid) return;
    final key = EncryptionUtil.aesKeyBase64;
    if (key != null) {
      await _serviceChannel.invokeMethod('setEncryptionKey', key);
    }
  }

  // On web, load the AES key that Android wrapped for this browser session
  // (stored at incoming_requests/{uid}/wrappedKey after Android accepts the
  // self-viewer request created when the user adds their own account on web).
  Future<void> _loadSelfDecryptionKey() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseDatabase.instance
        .ref('users/$uid/incoming_requests/$uid/wrappedKey')
        .get();
    final wrappedKey = snap.value as String?;
    if (wrappedKey == null) return;
    try {
      await EncryptionUtil.unwrapAndStoreRemoteKey(uid, wrappedKey);
    } catch (_) {}
  }

  Future<void> _checkPermission() async {
    if (!_isAndroid) return;
    final has = await _serviceChannel.invokeMethod<bool>('hasPermission') ?? false;
    if (has) {
      // If the app was killed, Android may have dropped the NLS binding even though the
      // permission is still granted. requestRebind reconnects it without user interaction.
      await _serviceChannel.invokeMethod('rebindListener');
      // Only auto-start if the user never explicitly stopped monitoring.
      final stopped = await _serviceChannel.invokeMethod<bool>('isMonitoringStopped') ?? false;
      if (!stopped && !_serviceRunning) await _startService();
    }
    setState(() => _hasPermission = has);
  }

  Future<void> _startService() async {
    if (!_isAndroid) return;
    await _serviceChannel.invokeMethod('startService');
    setState(() => _serviceRunning = true);
  }

  Future<void> _stopService() async {
    if (!_isAndroid) return;
    await _serviceChannel.invokeMethod('stopService');
    setState(() => _serviceRunning = false);
  }

  Future<void> _updateBadge(int count) async {
    try {
      if (_isMacOS) {
        await _badgeChannel.invokeMethod('setBadge', count);
      } else if (_isAndroid) {
        await _serviceChannel.invokeMethod('setBadge', count);
      }
    } catch (_) {}
  }

  void _onViewerNewCount(int count) {
    if (_viewerNewCount == count) return;
    setState(() => _viewerNewCount = count);
    _updateBadge(count);
  }

  Future<void> _openSettings() async {
    if (!_isAndroid) return;
    await _serviceChannel.invokeMethod('openSettings');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.appTitle),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: s.settingsTooltip,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        actions: const [],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          // Tab 0: Monitor
          if (!_isMonitoringSupported)
            const _UnsupportedPlatformCard()
          else
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverList.list(children: [
                    if (_isAndroid) ...[
                      _PermissionCard(hasPermission: _hasPermission, onGrant: _openSettings, onRevoke: _openSettings),
                      const SizedBox(height: 24),
                      _BackgroundMonitorCard(
                        hasPermission: _hasPermission,
                        running: _serviceRunning,
                        onStart: _startService,
                        onStop: _stopService,
                        onGrantPermission: _openSettings,
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_isMacOS) ...[
                      _MacOsBackgroundCard(),
                      const SizedBox(height: 24),
                      _CreateNotificationCard(),
                      const SizedBox(height: 24),
                    ],
                    _AccessRequestsCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RequestsScreen()),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
              ],
            ),
          // Tab 1: Visor
          ViewerScreen(
            isActive: _currentTab == 1,
            onNewCount: _onViewerNewCount,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.phone_android_outlined),
            selectedIcon: const Icon(Icons.phone_android),
            label: s.tabMonitor,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _viewerNewCount > 0,
              label: Text('$_viewerNewCount'),
              child: const Icon(Icons.visibility_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _viewerNewCount > 0,
              label: Text('$_viewerNewCount'),
              child: const Icon(Icons.visibility),
            ),
            label: s.tabViewer,
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final bool hasPermission;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;

  const _PermissionCard({required this.hasPermission, required this.onGrant, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    final granted = hasPermission;

    return Card(
      color: granted ? colors.primaryContainer : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  granted ? Icons.check_circle : Icons.warning,
                  color: granted ? colors.primary : colors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  s.notifAccess,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(granted ? s.permissionGranted : s.permissionNeeded),
            const SizedBox(height: 12),
            if (granted)
              OutlinedButton.icon(
                onPressed: onRevoke,
                icon: const Icon(Icons.block),
                label: Text(s.revokePermission),
              )
            else
              FilledButton.icon(
                onPressed: onGrant,
                icon: const Icon(Icons.settings),
                label: Text(s.grantPermission),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundMonitorCard extends StatelessWidget {
  final bool hasPermission;
  final bool running;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onGrantPermission;

  const _BackgroundMonitorCard({
    required this.hasPermission,
    required this.running,
    required this.onStart,
    required this.onStop,
    required this.onGrantPermission,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.sensors : Icons.sensors_off,
                  color: running ? colors.primary : colors.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  s.backgroundMonitor,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: running
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  running ? s.active : s.inactive,
                  style: TextStyle(
                    color: running ? colors.primary : colors.outline,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              !hasPermission
                  ? s.bgNeedsPermission
                  : running
                      ? s.bgRunning
                      : s.bgStopped,
            ),
            const SizedBox(height: 12),
            if (!hasPermission)
              FilledButton.icon(
                onPressed: onGrantPermission,
                icon: const Icon(Icons.settings),
                label: Text(s.grantPermission),
              )
            else if (!running)
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: Text(s.startMonitoring),
              )
            else
              OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: Text(s.stop),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedPlatformCard extends StatelessWidget {
  const _UnsupportedPlatformCard();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phonelink_off_outlined, size: 64, color: colors.outline),
            const SizedBox(height: 24),
            Text(
              s.monitoringUnsupportedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              s.monitoringUnsupportedBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessRequestsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AccessRequestsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final colors = Theme.of(context).colorScheme;

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref('users/$uid/incoming_requests')
          .onValue,
      builder: (context, snapshot) {
        int pending = 0;
        final data = snapshot.data?.snapshot.value;
        if (data != null) {
          pending = (data as Map)
              .values
              .where((v) => (v as Map)['status'] == 'pending')
              .length;
        }

        return Card(
          color: pending > 0 ? colors.errorContainer : null,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    color: pending > 0 ? colors.error : colors.outline,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.requestsTitle,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pending > 0
                              ? s.pendingRequestsBody(pending)
                              : s.noPendingRequests,
                          style: TextStyle(
                            color: pending > 0 ? colors.error : colors.outline,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pending > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$pending',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: colors.outline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MacOsBackgroundCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.sensors, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.backgroundMonitor,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.macOsBackground,
                    style: TextStyle(color: colors.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateNotificationCard extends StatefulWidget {
  @override
  State<_CreateNotificationCard> createState() => _CreateNotificationCardState();
}

class _CreateNotificationCardState extends State<_CreateNotificationCard> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
        title,
        body,
        const NotificationDetails(
          macOS: DarwinNotificationDetails(),
        ),
      );
      await _saveNotification({
        'source': 'manual',
        'appName': 'notification_reader',
        'packageName': 'com.jugomo.notification_reader',
        'title': title,
        'body': body,
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_alert, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  s.createNotification,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: s.titleLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: InputDecoration(
                labelText: s.bodyLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(s.sendNotification),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingApprovalScreen extends StatelessWidget {
  const _PendingApprovalScreen();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top_rounded, size: 64, color: colors.primary),
                const SizedBox(height: 24),
                Text(
                  s.pendingTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  s.pendingBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.outline, height: 1.5),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: Text(s.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

