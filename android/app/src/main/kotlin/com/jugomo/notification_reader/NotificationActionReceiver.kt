package com.jugomo.notification_reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_READ = "com.jugomo.notification_reader.READ_NOTIFICATIONS"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_READ) return
        val serviceIntent = Intent(context, LockScreenService::class.java).apply {
            action = LockScreenService.ACTION_READ_NOTIFICATIONS
        }
        context.startService(serviceIntent)
    }
}
