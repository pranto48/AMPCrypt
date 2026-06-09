import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/features/biometrics/data/datasources/fingerprint_verification_service.dart';
import 'package:ampcrypt/features/biometrics/data/datasources/voice_verification_service.dart';

void main() {
  group('FingerprintVerificationService Tests', () {
    late FingerprintVerificationService fingerprintService;

    setUp(() {
      fingerprintService = FingerprintVerificationService();
    });

    test('Should check biometric availability', () async {
      final available = await fingerprintService.isBiometricAvailable();
      // Biometrics are typically unavailable in headless test runner environment
      expect(available, isFalse);
    });
  });

  group('VoiceVerificationService Tests', () {
    late VoiceVerificationService voiceService;
    late File file1;
    late File file2;

    setUp(() async {
      voiceService = VoiceVerificationService();
      
      final tempDir = Directory.systemTemp;
      file1 = File('${tempDir.path}/voice1.wav');
      await file1.writeAsBytes([1, 2, 3, 4, 5]);

      file2 = File('${tempDir.path}/voice2.wav');
      await file2.writeAsBytes([5, 4, 3, 2, 1]);
    });

    tearDown(() async {
      if (await file1.exists()) await file1.delete();
      if (await file2.exists()) await file2.delete();
    });

    test('Should generate identical embeddings for identical files', () async {
      final emb1a = await voiceService.getVoiceEmbedding(file1);
      final emb1b = await voiceService.getVoiceEmbedding(file1);

      expect(emb1a, equals(emb1b));
      expect(voiceService.verifyVoiceMatch(emb1a, emb1b), isTrue);
    });

    test('Should generate different embeddings for different files', () async {
      final emb1 = await voiceService.getVoiceEmbedding(file1);
      final emb2 = await voiceService.getVoiceEmbedding(file2);

      expect(emb1, isNot(equals(emb2)));
      
      final similarity = voiceService.calculateCosineSimilarity(emb1, emb2);
      print('Voice cosine similarity: $similarity');
      
      expect(voiceService.verifyVoiceMatch(emb1, emb2, threshold: 0.8), isFalse);
    });
  });
}
