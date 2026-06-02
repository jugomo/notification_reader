package com.example.notification_reader

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val methodChannelName = "com.example.notification_reader/service"
    private val eventChannelName = "com.example.notification_reader/notifications"

    private val prefs by lazy { getSharedPreferences("app_prefs", Context.MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasNotificationListenerPermission())
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "startService" -> {
                        prefs.edit().putBoolean("monitoring_stopped", false).apply()
                        startForegroundService(Intent(this, LockScreenService::class.java))
                        // If the listener dropped its binding while monitoring was paused,
                        // toggle the component to force Android to reconnect it immediately.
                        if (NotificationReaderService.instance == null) {
                            val component = ComponentName(this, NotificationReaderService::class.java)
                            packageManager.setComponentEnabledSetting(
                                component,
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            packageManager.setComponentEnabledSetting(
                                component,
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                PackageManager.DONT_KILL_APP
                            )
                        }
                        result.success(null)
                    }
                    "stopService" -> {
                        prefs.edit().putBoolean("monitoring_stopped", true).apply()
                        stopService(Intent(this, LockScreenService::class.java))
                        result.success(null)
                    }
                    "isMonitoringStopped" -> {
                        result.success(prefs.getBoolean("monitoring_stopped", false))
                    }
                    "rebindListener" -> {
                        NotificationListenerService.requestRebind(
                            ComponentName(this, NotificationReaderService::class.java)
                        )
                        result.success(null)
                    }
                    "setBadge" -> {
                        val count = call.arguments as? Int ?: 0
                        val intent = Intent(this, LockScreenService::class.java).apply {
                            action = LockScreenService.ACTION_UPDATE_BADGE
                            putExtra(LockScreenService.EXTRA_BADGE_COUNT, count)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationReaderService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    NotificationReaderService.eventSink = null
                }
            })
    }

    private fun hasNotificationListenerPermission(): Boolean {
        val listeners = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return listeners.split(":").any { it.contains(packageName) }
    }
}
