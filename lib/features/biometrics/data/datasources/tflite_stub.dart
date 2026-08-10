/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

class InterpreterOptions {
  int threads = 0;
}

class Interpreter {
  static Future<Interpreter> fromAsset(String assetPath, {InterpreterOptions? options}) async {
    throw UnsupportedError('TFLite is not supported on Web.');
  }
  
  void run(Object input, Object output) {
    throw UnsupportedError('TFLite is not supported on Web.');
  }
}
