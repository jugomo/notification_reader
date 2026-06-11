package com.jugomo.notification_reader

import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.security.SecureRandom

/**
 * AES-256-GCM symmetric encryption matching the Dart EncryptionUtil.
 * The key is received from Flutter via MethodChannel and also persisted in
 * app_prefs so the NotificationListenerService can encrypt even when the
 * Flutter engine is not running.
 *
 * Encrypted format: "ENC:<iv_base64>:<ciphertext+tag_base64>"
 */
object EncryptionUtil {

    private var keyBytes: ByteArray? = null

    fun setKey(keyBase64: String) {
        keyBytes = Base64.decode(keyBase64, Base64.DEFAULT)
    }

    /** Returns the encrypted string, or the original plaintext if the key is not set. */
    fun encrypt(plaintext: String): String {
        val key = keyBytes ?: return plaintext
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(128, iv)
        )
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
        val ctB64 = Base64.encodeToString(ciphertext, Base64.NO_WRAP)
        return "ENC:$ivB64:$ctB64"
    }
}
