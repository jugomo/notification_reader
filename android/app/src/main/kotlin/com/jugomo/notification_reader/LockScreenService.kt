package com.jugomo.notification_reader

import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import java.util.Locale

class LockScreenService : Service() {

    companion object {
        const val CHANNEL_ID = "notif_reader_channel"
        const val NOTIF_ID = 1
        const val ACTION_UPDATE_BADGE = "com.jugomo.notification_reader.UPDATE_BADGE"
        const val ACTION_READ_NOTIFICATIONS = "com.jugomo.notification_reader.DO_READ"
        const val EXTRA_BADGE_COUNT = "badge_count"
    }

    private var badgeCount = 0
    private var tts: TextToSpeech? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIF_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE_BADGE -> {
                badgeCount = intent.getIntExtra(EXTRA_BADGE_COUNT, 0)
                getSystemService(NotificationManager::class.java)
                    .notify(NOTIF_ID, buildNotification())
            }
            ACTION_READ_NOTIFICATIONS -> readNotificationsAloud()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun readNotificationsAloud() {
        val service = NotificationReaderService.instance
        val text = if (service == null) {
            "El servicio de notificaciones no está activo."
        } else {
            val notifications = service.getCurrentNotifications().filter { !it.isOngoing }
            if (notifications.isEmpty()) {
                "No tienes notificaciones nuevas."
            } else {
                buildSpeechText(notifications)
            }
        }
        speak(text)
    }

    private fun buildSpeechText(
        notifications: List<android.service.notification.StatusBarNotification>
    ): String {
        val pm = packageManager
        val grouped = notifications.groupBy { it.packageName }
        val sb = StringBuilder()

        sb.append("Tienes ${notifications.size} notificaciones. ")

        grouped.forEach { (pkg, notifs) ->
            val appName = try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, PackageManager.GET_META_DATA)).toString()
            } catch (e: Exception) {
                pkg
            }

            if (notifs.size > 1) {
                sb.append("$appName, ${notifs.size} mensajes. ")
            } else {
                val extras = notifs.first().notification.extras
                val title = extras.getString("android.title") ?: ""
                val body = extras.getString("android.text") ?: ""
                val content = listOf(title, body).filter { it.isNotBlank() }.joinToString(": ")
                sb.append("$appName: $content. ")
            }
        }

        return sb.toString()
    }

    private fun speak(text: String) {
        tts?.stop()
        tts?.shutdown()
        tts = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                tts?.setAudioAttributes(audioAttributes)
                tts?.language = Locale("es", "ES")
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "read_notif")
            }
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lector de notificaciones",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val countText = if (badgeCount > 0) " · $badgeCount nueva${if (badgeCount != 1) "s" else ""}" else ""
        val readIntent = Intent(NotificationActionReceiver.ACTION_READ).apply {
            setPackage(packageName)
        }
        val pendingRead = PendingIntent.getBroadcast(
            this, 0, readIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingOpen = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Monitorizando notificaciones$countText")
                .setContentText("La app captura tus notificaciones en segundo plano")
                .setNumber(badgeCount)
                .setSmallIcon(Icon.createWithResource(this, android.R.drawable.ic_btn_speak_now))
                .setContentIntent(pendingOpen)
                .addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(this, android.R.drawable.ic_btn_speak_now),
                        "🔊 Leer notificaciones",
                        pendingRead
                    ).build()
                )
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Monitorizando notificaciones$countText")
                .setContentText("La app captura tus notificaciones en segundo plano")
                .setNumber(badgeCount)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentIntent(pendingOpen)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .build()
        }
    }
}
