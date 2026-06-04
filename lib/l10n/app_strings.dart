import 'package:flutter/material.dart';
import 'locale_provider.dart';

class S {
  final bool _en;
  const S._(this._en);

  static S of(BuildContext context) =>
      S._(LocaleNotifier.of(context).locale.languageCode == 'en');

  // ── General ───────────────────────────────────────────────────────────────
  String get appTitle => _en ? 'Notification Reader' : 'Lector de Notificaciones';
  String get settingsTitle => _en ? 'Settings' : 'Configuración';
  String get signOut => _en ? 'Sign out' : 'Cerrar sesión';
  String get language => _en ? 'Language' : 'Idioma';
  String get account => _en ? 'Account' : 'Cuenta';
  String get appearance => _en ? 'Appearance' : 'Apariencia';
  String get themeMode => _en ? 'Theme' : 'Tema';
  String get themeModeLight => _en ? 'Light' : 'Claro';
  String get themeModeDark => _en ? 'Dark' : 'Oscuro';
  String get themeModeSystem => _en ? 'Auto' : 'Auto';

  // ── AppBar / Navigation ───────────────────────────────────────────────────
  String get accessRequestsTooltip => _en ? 'Access requests' : 'Solicitudes de acceso';
  String get settingsTooltip => _en ? 'Settings' : 'Configuración';
  String get tabMonitor => 'Monitor';
  String get tabViewer => _en ? 'Viewer' : 'Visor';

  // ── Permission card ───────────────────────────────────────────────────────
  String get notifAccess => _en ? 'Notification Access' : 'Acceso a notificaciones';
  String get permissionGranted => _en
      ? 'Permission granted. The app can read your notifications.'
      : 'Permiso concedido. La app puede leer tus notificaciones.';
  String get permissionNeeded => _en
      ? 'You need to grant notification access for the app to work.'
      : 'Necesitas conceder acceso a las notificaciones para que la app funcione.';
  String get revokePermission => _en ? 'Revoke permission' : 'Revocar permiso';
  String get grantPermission => _en ? 'Grant permission' : 'Conceder permiso';

  // ── Background monitor card ───────────────────────────────────────────────
  String get backgroundMonitor =>
      _en ? 'Background Monitoring' : 'Monitorización en segundo plano';
  String get active => _en ? 'Active' : 'Activo';
  String get inactive => _en ? 'Inactive' : 'Inactivo';
  String get bgNeedsPermission => _en
      ? 'You need to grant notification access before enabling monitoring.'
      : 'Necesitas conceder acceso a las notificaciones antes de activar la monitorización.';
  String get bgRunning => _en
      ? 'The app captures notifications even when in the background or closed. A persistent notification appears in the system.'
      : 'La app captura notificaciones aunque esté en segundo plano o cerrada. Aparece una notificación persistente en el sistema.';
  String get bgStopped => _en
      ? 'Enable this service so the app keeps capturing notifications when in the background or closed.'
      : 'Activa este servicio para que la app siga capturando notificaciones cuando esté en segundo plano o cerrada.';
  String get startMonitoring => _en ? 'Start monitoring' : 'Iniciar monitorización';
  String get stop => _en ? 'Stop' : 'Detener';

  // ── Unsupported platform ──────────────────────────────────────────────────
  String get monitoringUnsupportedTitle => _en
      ? 'Notification monitoring not available'
      : 'Monitorización de notificaciones no disponible';
  String get monitoringUnsupportedBody => _en
      ? 'This feature lets the app capture all notifications received on your device and save them to the cloud, so you can review them later or share access with another user.\n\nBackground notification monitoring requires a system-level permission that is only supported on Android. It is not available on this device.'
      : 'Esta función permite que la app capture todas las notificaciones que recibes en tu dispositivo y las guarde en la nube, para que puedas revisarlas más tarde o compartir el acceso con otro usuario.\n\nLa monitorización de notificaciones en segundo plano requiere un permiso a nivel de sistema que solo está disponible en Android. No está disponible en este dispositivo.';

  // ── macOS card ────────────────────────────────────────────────────────────
  String get macOsBackground => _en
      ? 'The app keeps running when the window is closed. Reopen from the Dock.'
      : 'La app sigue ejecutándose al cerrar la ventana. Reabre desde el Dock.';

  // ── Create notification card (macOS) ──────────────────────────────────────
  String get createNotification => _en ? 'Create notification' : 'Crear notificación';
  String get titleLabel => _en ? 'Title' : 'Título';
  String get bodyLabel => _en ? 'Body' : 'Cuerpo';
  String get sendNotification => _en ? 'Send notification' : 'Enviar notificación';

  // ── Pending approval screen ───────────────────────────────────────────────
  String get pendingTitle =>
      _en ? 'Account pending activation' : 'Cuenta pendiente de activación';
  String get pendingBody => _en
      ? 'Your account has been created successfully, but it needs to be activated by an administrator before you can access it.\n\nWhen the administrator activates your account, the app will open automatically.'
      : 'Tu cuenta ha sido creada correctamente, pero necesita ser activada por un administrador antes de poder acceder.\n\nCuando el administrador active tu cuenta, la app se abrirá automáticamente.';

  // ── Notifications list ────────────────────────────────────────────────────
  String get deleteAll => _en ? 'Delete all' : 'Borrar todas';
  String get deleteAllConfirmTitle => _en ? 'Delete all notifications?' : '¿Borrar todas las notificaciones?';
  String get deleteAllConfirmBody => _en ? 'This action cannot be undone.' : 'Esta acción no se puede deshacer.';
  String get noNotificationsYet => _en ? 'No notifications yet' : 'Sin notificaciones aún';
  String get noMonitoredDevices => _en ? 'No monitored devices currently' : 'Sin dispositivos monitorizados actualmente';
  String get tapPlusToAdd => _en ? 'Tap + to add a device' : 'Pulsa + para añadir un dispositivo';
  String get noTitle => _en ? 'No title' : 'Sin título';

  // ── Auth screen ───────────────────────────────────────────────────────────
  String get loginSubtitle => _en ? 'Sign in to continue' : 'Inicia sesión para continuar';
  String get registerSubtitle => _en ? 'Create your account' : 'Crea tu cuenta';
  String get emailLabel => _en ? 'Email' : 'Correo electrónico';
  String get passwordLabel => _en ? 'Password' : 'Contraseña';
  String get login => _en ? 'Sign in' : 'Iniciar sesión';
  String get register => _en ? 'Create account' : 'Crear cuenta';
  String get noAccount =>
      _en ? "Don't have an account? Sign up" : '¿No tienes cuenta? Regístrate';
  String get hasAccount =>
      _en ? 'Already have an account? Sign in' : '¿Ya tienes cuenta? Inicia sesión';
  String get enterEmail => _en ? 'Enter your email.' : 'Ingresa tu correo.';
  String get invalidEmail => _en ? 'Invalid email.' : 'Correo no válido.';
  String get enterPassword => _en ? 'Enter your password.' : 'Ingresa tu contraseña.';
  String get minPassword => _en ? 'Minimum 6 characters.' : 'Mínimo 6 caracteres.';
  String authError(String code) => switch (code) {
        'user-not-found' => _en
            ? 'No account found with that email.'
            : 'No existe una cuenta con ese correo.',
        'wrong-password' =>
          _en ? 'Incorrect password.' : 'Contraseña incorrecta.',
        'email-already-in-use' => _en
            ? 'An account with that email already exists.'
            : 'Ya existe una cuenta con ese correo.',
        'weak-password' => _en
            ? 'Password must be at least 6 characters.'
            : 'La contraseña debe tener al menos 6 caracteres.',
        'invalid-email' => _en
            ? 'Email format is not valid.'
            : 'El correo no tiene un formato válido.',
        'invalid-credential' =>
          _en ? 'Invalid credentials.' : 'Credenciales incorrectas.',
        'too-many-requests' => _en
            ? 'Too many attempts. Try again later.'
            : 'Demasiados intentos. Intenta más tarde.',
        _ => _en ? 'Unexpected error ($code).' : 'Error inesperado ($code).',
      };

  // ── Access requests card ──────────────────────────────────────────────────
  String get noPendingRequests => _en ? 'No pending requests' : 'Sin solicitudes pendientes';
  String pendingRequestsBody(int n) => _en
      ? '$n pending request${n == 1 ? '' : 's'}'
      : '$n solicitud${n == 1 ? '' : 'es'} pendiente${n == 1 ? '' : 's'}';

  // ── Requests screen ───────────────────────────────────────────────────────
  String get requestsTitle => _en ? 'Access Requests' : 'Solicitudes de acceso';
  String get noRequests => _en ? 'No requests' : 'No tienes solicitudes';
  String get accept => _en ? 'Accept' : 'Aceptar';
  String get reject => _en ? 'Reject' : 'Rechazar';
  String get revokeAccess => _en ? 'Revoke access' : 'Revocar acceso';
  String get statusAccepted => _en ? 'Accepted' : 'Aceptada';
  String get statusRejected => _en ? 'Rejected' : 'Rechazada';
  String get statusPending => _en ? 'Pending' : 'Pendiente';
  String get sectionGrantedAccess => _en ? 'With access' : 'Con acceso';
  String get sectionPendingRequests => _en ? 'Pending requests' : 'Solicitudes pendientes';
  String get sectionRejected => _en ? 'Rejected' : 'Rechazadas';

  // ── Account ───────────────────────────────────────────────────────────────
  String get deleteAccount => _en ? 'Delete account' : 'Eliminar cuenta';
  String get deleteAccountConfirmTitle =>
      _en ? 'Delete account?' : '¿Eliminar cuenta?';
  String get deleteAccountConfirmBody => _en
      ? 'All your notifications, settings, and account data will be permanently deleted. This action cannot be undone.'
      : 'Todas tus notificaciones, ajustes y datos de cuenta serán eliminados permanentemente. Esta acción no se puede deshacer.';
  String get deleteAccountError => _en
      ? 'Could not delete the account. Sign out and back in, then try again.'
      : 'No se pudo eliminar la cuenta. Cierra sesión, vuelve a entrar e inténtalo de nuevo.';
  String get reauthTitle =>
      _en ? 'Confirm your password' : 'Confirma tu contraseña';
  String get reauthBody => _en
      ? 'Enter your password to confirm account deletion.'
      : 'Ingresa tu contraseña para confirmar la eliminación de la cuenta.';
  String get delete => _en ? 'Delete' : 'Eliminar';

  // ── Notifications ─────────────────────────────────────────────────────────
  String get notifications => _en ? 'Notifications' : 'Notificaciones';
  String get viewerSoundLabel => _en ? 'Sound on new notification' : 'Sonido al recibir notificación';
  String get viewerSoundSubtitle => _en
      ? 'Play a chime when a new notification arrives in the Viewer tab'
      : 'Reproduce un sonido cuando llega una notificación en la pestaña Visor';

  // ── Settings tabs ─────────────────────────────────────────────────────────
  String get tabSettings => _en ? 'Settings' : 'Ajustes';
  String get tabAbout => _en ? 'About' : 'Acerca de';
  String get aboutDescription => _en
      ? 'Notification Reader captures all notifications received on your Android device and syncs them to the cloud in real time, so you can review them later or share access with another user.\n\nIt includes background monitoring, lock-screen TTS playback, multi-user viewer mode, and Firebase-powered sync.'
      : 'Lector de Notificaciones captura todas las notificaciones que recibes en tu dispositivo Android y las sincroniza en la nube en tiempo real, para que puedas revisarlas después o compartir el acceso con otro usuario.\n\nIncluye monitorización en segundo plano, lectura en voz alta desde la pantalla de bloqueo, modo visor multiusuario y sincronización con Firebase.';
  String get version => _en ? 'Version' : 'Versión';

  // ── Viewer screen ─────────────────────────────────────────────────────────
  String get thisDevice => _en ? 'This device' : 'Este dispositivo';
  String get addDevice => _en ? 'Add device' : 'Añadir dispositivo';
  String get alreadyMonitoring =>
      _en ? 'Already monitoring this device' : 'Ya monitorizas este dispositivo';
  String get viewerTitle =>
      _en ? "View another user's notifications" : 'Ver notificaciones de otro usuario';
  String get viewerSubtitle => _en
      ? 'Enter the email of the user whose notifications you want to monitor. That user will need to accept your request.'
      : 'Ingresa el email del usuario cuyas notificaciones quieres monitorear. Ese usuario deberá aceptar tu solicitud.';
  String get userEmail => _en ? 'User email' : 'Email del usuario';
  String get userNotFound => _en ? 'User not found' : 'Usuario no encontrado';
  String get sendRequest => _en ? 'Send request' : 'Enviar solicitud';
  String get requestSent => _en ? 'Request sent' : 'Solicitud enviada';
  String awaitingConsent(String email) => _en
      ? 'Waiting for $email to accept your request...'
      : 'Esperando que $email acepte tu solicitud...';
  String get cancel => _en ? 'Cancel' : 'Cancelar';
  String viewingNotifs(String email) =>
      _en ? 'Viewing notifications of $email' : 'Viendo notificaciones de $email';
  String get change => _en ? 'Change' : 'Cambiar';
  String get requestRejectedTitle => _en ? 'Request rejected' : 'Solicitud rechazada';
  String requestRejectedBy(String email) =>
      _en ? '$email rejected your request.' : '$email rechazó tu solicitud.';
  String get back => _en ? 'Back' : 'Volver';
  String get deleteEntry => _en ? 'Delete' : 'Eliminar';

  // ── Errors ────────────────────────────────────────────────────────────────
  String get requestFailed => _en
      ? 'Could not send request. Check your connection and try again.'
      : 'No se pudo enviar la solicitud. Comprueba tu conexión e inténtalo de nuevo.';
  String get loadError => _en
      ? 'Failed to load data. Check your connection.'
      : 'Error al cargar los datos. Comprueba tu conexión.';
}
