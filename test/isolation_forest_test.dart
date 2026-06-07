import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/core/ml/isolation_forest.dart';

void main() {
  group('IsolationForest Tests', () {
    test('Should train and identify outliers with higher anomaly scores', () {
      // 1. Generate normal training data clustered around (1.0, 1.0)
      final List<List<double>> trainingData = [];
      for (int i = 0; i < 100; i++) {
        // Points randomly distributed slightly around (1.0, 1.0)
        double offsetX = (i % 10) * 0.05;
        double offsetY = (i ~/ 10) * 0.05;
        trainingData.add([1.0 + offsetX, 1.0 + offsetY]);
      }

      // 2. Initialize and fit forest
      final forest = IsolationForest(numTrees: 50, subsampleSize: 64);
      expect(forest.isTrained, isFalse);

      forest.fit(trainingData);
      expect(forest.isTrained, isTrue);

      // 3. Evaluate normal points (should be close to training cluster)
      final double normalScore = forest.evaluate([1.2, 1.2]);
      
      // 4. Evaluate anomalous points (outliers, far from cluster)
      final double anomalyScore = forest.evaluate([10.0, 10.0]);

      // 5. Assertions
      print('Normal point score: $normalScore');
      print('Anomalous point score: $anomalyScore');

      // Anomalies should score significantly higher than normal points
      expect(anomalyScore, greaterThan(normalScore));
      
      // Typical thresholds
      expect(normalScore, lessThan(0.55));
      expect(anomalyScore, greaterThan(0.6));
    });

    test('Should throw StateError if evaluated before training', () {
      final forest = IsolationForest();
      expect(() => forest.evaluate([1.0, 1.0]), throwsStateError);
    });

    test('Should throw ArgumentError on empty training set', () {
      final forest = IsolationForest();
      expect(() => forest.fit([]), throwsArgumentError);
    });
  });
}
