import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/features/ransomware_monitor/data/datasources/directory_watcher_service.dart';
import 'package:ampcrypt/features/ransomware_monitor/data/models/sliding_window_features.dart';

void main() {
  group('DirectoryWatcherService Tests', () {
    late Directory tempDir;
    late DirectoryWatcherService watcherService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ampcrypt_watcher_test');
      watcherService = DirectoryWatcherService();
    });

    tearDown(() async {
      watcherService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Should capture file events and compute positive write and delete rates', () async {
      final featuresList = <SlidingWindowFeatures>[];

      // 1. Start watching
      watcherService.startWatching(tempDir.path);
      expect(watcherService.isWatching, isTrue);
      expect(watcherService.watchedPath, tempDir.path);

      // Listen to the features stream
      final subscription = watcherService.featuresStream.listen((features) {
        featuresList.add(features);
      });

      // 2. Perform rapid file writes and deletes to simulate activity
      final List<File> files = [];
      for (int i = 0; i < 10; i++) {
        final file = File('${tempDir.path}/test_file_$i.txt');
        await file.writeAsString('Normal content simulation');
        files.add(file);
      }

      // Modify files
      for (final file in files) {
        await file.writeAsString('Updated content simulation');
      }

      // Delete files
      for (final file in files) {
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Wait 1.5 seconds for the timer to process the window and produce at least one output
      await Future.delayed(const Duration(milliseconds: 1500));

      await subscription.cancel();
      watcherService.stopWatching();

      expect(featuresList, isNotEmpty);
      final lastFeatures = featuresList.last;
      print('Calculated features after simulation: $lastFeatures');

      // Check that it captured write and delete actions
      expect(lastFeatures.writeRate, greaterThan(0.0));
      expect(lastFeatures.deleteRate, greaterThan(0.0));
    });
  });
}
