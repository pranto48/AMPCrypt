import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/features/biometrics/data/datasources/face_verification_service.dart';

void main() {
  group('FaceVerificationService Tests', () {
    late FaceVerificationService faceService;
    late File file1;
    late File file2;

    setUp(() async {
      faceService = FaceVerificationService();
      
      // Create two temp dummy files with different content
      final tempDir = Directory.systemTemp;
      file1 = File('${tempDir.path}/face1.png');
      await file1.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      file2 = File('${tempDir.path}/face2.png');
      await file2.writeAsBytes([10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
    });

    tearDown(() async {
      if (await file1.exists()) await file1.delete();
      if (await file2.exists()) await file2.delete();
    });

    test('Should generate identical embeddings for identical files', () async {
      final emb1a = await faceService.getFaceEmbedding(file1);
      final emb1b = await faceService.getFaceEmbedding(file1);

      expect(emb1a, equals(emb1b));
      expect(faceService.verifyMatch(emb1a, emb1b), isTrue);
    });

    test('Should generate different embeddings for different files', () async {
      final emb1 = await faceService.getFaceEmbedding(file1);
      final emb2 = await faceService.getFaceEmbedding(file2);

      expect(emb1, isNot(equals(emb2)));
      
      final distance = faceService.calculateDistance(emb1, emb2);
      print('Distance between different files: $distance');
      
      // Should fail verification due to distance threshold
      expect(faceService.verifyMatch(emb1, emb2, threshold: 0.6), isFalse);
    });
  });
}
