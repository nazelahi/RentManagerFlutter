import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Port of `src/utils/biometricAuth.ts` + SecureAuthenticationService gate.
class BiometricAuth {
  static final _auth = LocalAuthentication();

  /// Checks if biometrics or device credentials (PIN/pattern/passcode) are supported.
  static Future<bool> get isAvailable async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported || canCheck;
    } catch (e) {
      debugPrint('BiometricAuth.isAvailable error: $e');
      return false;
    }
  }

  /// Lists available biometric hardware types (fingerprint, face, etc.)
  static Future<List<BiometricType>> get availableBiometrics async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('BiometricAuth.availableBiometrics error: $e');
      return [];
    }
  }

  /// Checks if fingerprint hardware is available / enrolled.
  static Future<bool> get hasFingerprint async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong)) {
        return true;
      }
      return await isAvailable;
    } catch (_) {
      return false;
    }
  }

  /// Checks if face hardware is available / enrolled.
  static Future<bool> get hasFace async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face) ||
          types.contains(BiometricType.weak)) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts for authentication. Supports fingerprint, face, or device PIN/pattern fallback.
  static Future<bool> authenticate({
    String localizedReason = 'Authenticate to access RentManager',
  }) async {
    try {
      final available = await isAvailable;
      if (!available) return false;

      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric authentication failed: $e');
      return false;
    }
  }
}
