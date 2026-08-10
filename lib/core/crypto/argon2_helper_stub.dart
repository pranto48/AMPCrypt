/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:typed_data';

Future<Uint8List> deriveArgon2Key(String password, Uint8List salt) async {
  throw UnsupportedError("Argon2 key derivation is not supported on this platform.");
}
