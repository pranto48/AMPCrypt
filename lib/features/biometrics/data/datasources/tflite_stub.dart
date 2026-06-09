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
