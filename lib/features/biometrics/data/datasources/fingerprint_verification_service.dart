/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'package:local_auth/local_auth.dart';

/// Service to handle Hardware Fingerprint scanning using local_auth.
class FingerprintVerificationService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Checks if biometrics are supported and active on the device.
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      return false;
    }
  }

  /// Triggers the device biometric authentication prompt.
  Future<bool> authenticateFingerprint() async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to validate SSS factor share',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return didAuthenticate;
    } catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }
}
