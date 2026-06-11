package com.jugomo.notification_reader

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class NotificationReaderService : NotificationListenerService() {

    companion object {
        var instance: NotificationReaderService? = null
        var eventSink: EventChannel.EventSink? = null
    }

    // Tracks the last title|body seen per notification key to skip pure-update re-posts.
    private val lastSeen = HashMap<String, String>()

    private val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    override fun onListenerConnected() {
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
        // requestRebind() is unreliable on many Android versions. Toggling the component's
        // enabled state forces the OS to rebind as if the permission was toggled by the user.
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

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName == packageName) return

        // Respect the user's explicit stop — block capture in foreground, background, and closed.
        val prefs = applicationContext.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("monitoring_stopped", false)) return

        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val body = extras.getCharSequence("android.text")?.toString() ?: ""

        // Skip saves when an app re-posts the same notification as an update (same content).
        val fingerprint = "$title|$body"
        if (lastSeen[sbn.key] == fingerprint) return
        lastSeen[sbn.key] = fingerprint

        val appName = try {
            val info = applicationContext.packageManager.getApplicationInfo(sbn.packageName, 0)
            applicationContext.packageManager.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            sbn.packageName
        }

        val receivedAt = isoFormat.format(Date())

        // Load the encryption key (set by Flutter on launch; persisted so it's
        // available here even when the Flutter engine is not running).
        val encKey = prefs.getString("enc_key", null)
        if (encKey != null) EncryptionUtil.setKey(encKey)

        // Write directly to Firebase — works even when the Flutter engine is not running
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid != null) {
            FirebaseDatabase.getInstance().reference
                .child("users/$uid/notifications")
                .push()
                .setValue(
                    mapOf(
                        "source" to "system",
                        "packageName" to sbn.packageName,
                        "appName" to EncryptionUtil.encrypt(appName),
                        "title" to EncryptionUtil.encrypt(title),
                        "body" to EncryptionUtil.encrypt(body),
                        "receivedAt" to receivedAt,
                    )
                )
        }

        // If the monitoring notification was dismissed (e.g. process killed), re-post it.
        // At this point monitoring_stopped is guaranteed false (we returned early above if true).
        val nm = getSystemService(NotificationManager::class.java)
        val isShowing = nm.activeNotifications.any { it.id == LockScreenService.NOTIF_ID }
        if (!isShowing) {
            val serviceIntent = Intent(applicationContext, LockScreenService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(serviceIntent)
            } else {
                applicationContext.startService(serviceIntent)
            }
        }

        // Notify the Flutter UI if it is alive (used only for live UI updates, not for persistence)
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(
                mapOf(
                    "source" to "system",
                    "packageName" to sbn.packageName,
                    "appName" to appName,
                    "title" to title,
                    "body" to body,
                    "receivedAt" to sbn.postTime,
                )
            )
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        lastSeen.remove(sbn.key)
    }

    fun getCurrentNotifications(): List<StatusBarNotification> {
        return try {
            activeNotifications?.toList() ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }
}
