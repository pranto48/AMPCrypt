/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:argon2/argon2.dart';

Future<Uint8List> deriveArgon2Key(String password, Uint8List salt) async {
  final parameters = Argon2Parameters(
    Argon2Parameters.ARGON2_id,
    salt,
    version: Argon2Parameters.ARGON2_VERSION_13,
    iterations: 3,
    memoryPowerOf2: 15,
    lanes: 2,
  );
  final generator = Argon2BytesGenerator();
  generator.init(parameters);

  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  final hash = Uint8List(32);
  generator.generateBytes(passwordBytes, hash, 0, hash.length);
  return hash;
}
