import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'books.dart';

/// App lock: a 4–6 digit PIN (stored only as a salted hash) and optional
/// fingerprint / face unlock.
class AppLock {
  static final _auth = LocalAuthentication();

  static String _hash(String pin) => sha256.convert(utf8.encode('gamex-hisab:$pin')).toString();

  static Future<bool> enabled() async => ((await Books.settings())['lock_pin'] ?? '').isNotEmpty;

  static Future<bool> biometricOn() async => (await Books.settings())['lock_bio'] == '1';

  /// Seconds in the background before the app locks again (0 = at once).
  static Future<int> lockAfter() async => int.tryParse((await Books.settings())['lock_after'] ?? '') ?? 30;

  static Future<bool> check(String pin) async => (await Books.settings())['lock_pin'] == _hash(pin);

  static Future<void> setPin(String pin) => Books.setSetting('lock_pin', _hash(pin));

  static Future<void> disable() async {
    await Books.setSetting('lock_pin', '');
    await Books.setSetting('lock_bio', '0');
  }

  static Future<bool> canUseBiometrics() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock GameX Hisab',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
