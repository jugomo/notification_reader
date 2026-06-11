import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart';
// Hide flutter's Key to avoid ambiguity with encrypt's Key.
import 'package:flutter/foundation.dart' hide Key;
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level function required by [compute] (must not be a closure).
Map<String, String> _generateRSAKeyPairIsolate(int bitStrength) {
  final secureRandom = FortunaRandom();
  secureRandom.seed(
    KeyParameter(Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    )),
  );
  final keyGen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.parse('65537'), bitStrength, 64),
      secureRandom,
    ));
  final pair = keyGen.generateKeyPair();
  final pub = pair.publicKey as RSAPublicKey;
  final priv = pair.privateKey as RSAPrivateKey;
  return {
    'n': pub.modulus!.toRadixString(16),
    'e': pub.exponent!.toRadixString(16),
    'd': priv.privateExponent!.toRadixString(16),
    'p': priv.p!.toRadixString(16),
    'q': priv.q!.toRadixString(16),
  };
}

/// Symmetric + asymmetric encryption for notification data in Firebase.
///
/// Each device owns:
///   - An AES-256-GCM key  — encrypts its own notifications.
///   - An RSA-2048 key pair — used to share the AES key with authorised viewers.
///
/// Encrypted format: `ENC:<iv_b64>:<ciphertext_b64>` (12-byte GCM IV, 128-bit tag).
/// Plain / legacy values (no `ENC:` prefix) pass through unchanged.
class EncryptionUtil {
  static const _aesKeyPref = 'notif_enc_key';
  static const _rsaPrivPref = 'notif_rsa_priv';
  static const _rsaPubPref = 'notif_rsa_pub';
  static const _remotePref = 'notif_remote_keys';

  static Key? _aesKey;
  static String? _aesKeyBase64;
  static RSAPublicKey? _rsaPublicKey;
  static RSAPrivateKey? _rsaPrivateKey;
  static String? _rsaPublicKeyBase64;

  /// Remote devices' AES keys: ownerUid → Key.
  static final Map<String, Key> _remoteKeys = {};

  /// Own Firebase UID — set via [setOwnUid] after login.
  static String? _ownUid;

  static String? get aesKeyBase64 => _aesKeyBase64;

  /// Base64-encoded RSA public key for storing in the Firebase profile.
  static String? get rsaPublicKeyBase64 => _rsaPublicKeyBase64;

  static void setOwnUid(String uid) => _ownUid = uid;
  static bool hasRemoteKey(String uid) => _remoteKeys.containsKey(uid);

  /// Initialises AES key, RSA key pair, and loads persisted remote keys.
  /// Must be called before any encrypt/decrypt operation.
  static Future<void> init() async {
    await _initAesKey();
    await _initRsaKeyPair();
    await _loadRemoteKeys();
  }

  // ── AES-256-GCM ─────────────────────────────────────────────────────────────

  static Future<void> _initAesKey() async {
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString(_aesKeyPref);
    if (stored == null) {
      final bytes = Uint8List(32);
      final rng = Random.secure();
      for (var i = 0; i < 32; i++) {
        bytes[i] = rng.nextInt(256);
      }
      stored = base64.encode(bytes);
      await prefs.setString(_aesKeyPref, stored);
    }
    _aesKeyBase64 = stored;
    _aesKey = Key(base64.decode(stored));
  }

  /// Encrypts [plaintext] with the device's own AES key.
  static String encrypt(String plaintext) {
    final key = _aesKey;
    if (key == null) return plaintext;
    return _aesEncrypt(plaintext, key);
  }

  /// Decrypts [value] using the key that belongs to [ownerUid].
  ///
  /// Remote key takes precedence over the local AES key — this handles
  /// cross-device viewing of own notifications (e.g. web viewing Android-encrypted
  /// data after Android wrapped its AES key for this browser session).
  static String decryptForUid(String value, String ownerUid) {
    if (!value.startsWith('ENC:')) return value;
    final key = _remoteKeys[ownerUid] ??
        (ownerUid.isEmpty || ownerUid == _ownUid ? _aesKey : null);
    if (key == null) return value;
    return _aesDecrypt(value, key);
  }

  /// Decrypts [value] with the own AES key (backward compat).
  static String decrypt(String value) => decryptForUid(value, _ownUid ?? '');

  static String _aesEncrypt(String plaintext, Key key) {
    final iv = IV.fromSecureRandom(12);
    final encrypted =
        Encrypter(AES(key, mode: AESMode.gcm)).encrypt(plaintext, iv: iv);
    return 'ENC:${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  static String _aesDecrypt(String value, Key key) {
    try {
      final rest = value.substring(4);
      final sep = rest.indexOf(':');
      if (sep < 0) return value;
      final iv = IV(base64.decode(rest.substring(0, sep)));
      final ct = Encrypted(base64.decode(rest.substring(sep + 1)));
      return Encrypter(AES(key, mode: AESMode.gcm)).decrypt(ct, iv: iv);
    } catch (_) {
      return value;
    }
  }

  // ── RSA-2048-OAEP key wrapping ───────────────────────────────────────────────

  static Future<void> _initRsaKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final privStored = prefs.getString(_rsaPrivPref);
    final pubStored = prefs.getString(_rsaPubPref);

    if (privStored != null && pubStored != null) {
      _rsaPublicKey = _pubKeyFromBase64(pubStored);
      _rsaPrivateKey = _privKeyFromBase64(privStored);
      _rsaPublicKeyBase64 = pubStored;
    } else {
      // RSA-2048 generation is slow — offload to a background isolate.
      final data = await compute(_generateRSAKeyPairIsolate, 2048);
      _rsaPublicKey = RSAPublicKey(
        BigInt.parse(data['n']!, radix: 16),
        BigInt.parse(data['e']!, radix: 16),
      );
      _rsaPrivateKey = RSAPrivateKey(
        BigInt.parse(data['n']!, radix: 16),
        BigInt.parse(data['d']!, radix: 16),
        BigInt.parse(data['p']!, radix: 16),
        BigInt.parse(data['q']!, radix: 16),
      );
      final pubBase64 = _pubKeyToBase64(_rsaPublicKey!);
      final privBase64 = _privKeyToBase64(_rsaPrivateKey!);
      await prefs.setString(_rsaPubPref, pubBase64);
      await prefs.setString(_rsaPrivPref, privBase64);
      _rsaPublicKeyBase64 = pubBase64;
    }
  }

  /// Encrypts (wraps) the device's own AES key with [recipientPublicKeyBase64]
  /// so the recipient can unwrap it with their RSA private key.
  static String wrapAesKeyFor(String recipientPublicKeyBase64) {
    final recipientKey = _pubKeyFromBase64(recipientPublicKeyBase64);
    final cipher = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(recipientKey));
    final aesBytes = base64.decode(_aesKeyBase64!);
    final wrapped = cipher.process(Uint8List.fromList(aesBytes));
    return base64.encode(wrapped);
  }

  /// Decrypts [wrappedKeyBase64] with the own RSA private key and stores the
  /// resulting AES key so [ownerUid]'s notifications can be read.
  static Future<void> unwrapAndStoreRemoteKey(
    String ownerUid,
    String wrappedKeyBase64,
  ) async {
    final cipher = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(_rsaPrivateKey!));
    final wrapped = base64.decode(wrappedKeyBase64);
    final aesBytes = cipher.process(Uint8List.fromList(wrapped));
    _remoteKeys[ownerUid] = Key(aesBytes);
    await _persistRemoteKeys();
  }

  /// Removes [ownerUid]'s key from local storage when access is revoked.
  static Future<void> removeRemoteKey(String ownerUid) async {
    _remoteKeys.remove(ownerUid);
    await _persistRemoteKeys();
  }

  static Future<void> _loadRemoteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_remotePref);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in map.entries) {
      _remoteKeys[entry.key] = Key(base64.decode(entry.value as String));
    }
  }

  static Future<void> _persistRemoteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _remoteKeys.map(
      (uid, key) => MapEntry(uid, base64.encode(key.bytes)),
    );
    await prefs.setString(_remotePref, jsonEncode(map));
  }

  // ── RSA key serialization: BigInt hex → JSON → base64 ───────────────────────

  static String _pubKeyToBase64(RSAPublicKey key) => base64.encode(utf8.encode(
        jsonEncode({
          'n': key.modulus!.toRadixString(16),
          'e': key.exponent!.toRadixString(16),
        }),
      ));

  static RSAPublicKey _pubKeyFromBase64(String encoded) {
    final data = jsonDecode(utf8.decode(base64.decode(encoded))) as Map;
    return RSAPublicKey(
      BigInt.parse(data['n'] as String, radix: 16),
      BigInt.parse(data['e'] as String, radix: 16),
    );
  }

  static String _privKeyToBase64(RSAPrivateKey key) =>
      base64.encode(utf8.encode(
        jsonEncode({
          'n': key.modulus!.toRadixString(16),
          'd': key.privateExponent!.toRadixString(16),
          'p': key.p!.toRadixString(16),
          'q': key.q!.toRadixString(16),
        }),
      ));

  static RSAPrivateKey _privKeyFromBase64(String encoded) {
    final data = jsonDecode(utf8.decode(base64.decode(encoded))) as Map;
    return RSAPrivateKey(
      BigInt.parse(data['n'] as String, radix: 16),
      BigInt.parse(data['d'] as String, radix: 16),
      BigInt.parse(data['p'] as String, radix: 16),
      BigInt.parse(data['q'] as String, radix: 16),
    );
  }
}
