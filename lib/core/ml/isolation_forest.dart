import 'dart:math';

/// A node in an Isolation Tree (iTree).
class IsolationTree {
  final IsolationTree? left;
  final IsolationTree? right;
  final int? splitFeature;
  final double? splitValue;
  final int size; // Number of training instances in this node
  final bool isLeaf;

  IsolationTree.leaf({required this.size})
      : left = null,
        right = null,
        splitFeature = null,
        splitValue = null,
        isLeaf = true;

  IsolationTree.internal({
    required this.left,
    required this.right,
    required this.splitFeature,
    required this.splitValue,
    required this.size,
  }) : isLeaf = false;
}

/// An Isolation Forest model for unsupervised anomaly detection.
class IsolationForest {
  final int numTrees;
  final int subsampleSize;
  late final List<IsolationTree> _trees;
  late final int _maxHeight;
  bool _isTrained = false;

  bool get isTrained => _isTrained;

  IsolationForest({
    this.numTrees = 100,
    this.subsampleSize = 256,
  });

  /// Fits the model to a training dataset [X].
  /// [X] is a list of feature vectors, where each feature vector is a list of doubles.
  void fit(List<List<double>> X) {
    if (X.isEmpty) {
      throw ArgumentError('Training dataset cannot be empty.');
    }

    final int n = X.length;
    final int sampleSize = min(subsampleSize, n);
    
    // Set max height of trees to ceil(log2(sampleSize))
    _maxHeight = (log(sampleSize) / log(2.0)).ceil();
    _trees = [];
    final Random random = Random();

    for (int i = 0; i < numTrees; i++) {
      // Draw subsamples randomly without replacement
      final List<List<double>> subsample = [];
      final List<int> indices = List.generate(n, (index) => index)..shuffle(random);
      for (int j = 0; j < sampleSize; j++) {
        subsample.add(X[indices[j]]);
      }

      _trees.add(_buildTree(subsample, 0, _maxHeight));
    }

    _isTrained = true;
  }

  /// Evaluates a single data instance [x] and returns its anomaly score between 0.0 and 1.0.
  /// A score close to 1.0 indicates a high probability of anomaly, while a score < 0.5 is normal.
  double evaluate(List<double> x) {
    if (!_isTrained) {
      throw StateError('Model must be trained before evaluation.');
    }
    if (_trees.isEmpty) return 0.5;

    double sumPathLength = 0.0;
    for (final tree in _trees) {
      sumPathLength += _pathLength(x, tree, 0);
    }

    final double meanPathLength = sumPathLength / _trees.length;
    final double avgC = _c(subsampleSize);
    
    if (avgC == 0.0) return 0.0;
    return pow(2.0, -meanPathLength / avgC).toDouble();
  }

  /// Builds a single Isolation Tree (iTree) recursively.
  IsolationTree _buildTree(List<List<double>> X, int currentHeight, int maxHeight) {
    if (X.length <= 1 || currentHeight >= maxHeight) {
      return IsolationTree.leaf(size: X.length);
    }

    final int numFeatures = X[0].length;
    final Random random = Random();
    
    // Randomly select a feature to split on
    int splitFeature = random.nextInt(numFeatures);
    
    // Find min and max value for this feature in the current dataset subset
    double minVal = X[0][splitFeature];
    double maxVal = X[0][splitFeature];
    for (final row in X) {
      if (row[splitFeature] < minVal) minVal = row[splitFeature];
      if (row[splitFeature] > maxVal) maxVal = row[splitFeature];
    }

    // If there is no variance in this feature, attempt to find another feature
    if (minVal == maxVal) {
      final List<int> features = List.generate(numFeatures, (i) => i)..shuffle(random);
      bool foundVariance = false;
      for (final f in features) {
        minVal = X[0][f];
        maxVal = X[0][f];
        for (final row in X) {
          if (row[f] < minVal) minVal = row[f];
          if (row[f] > maxVal) maxVal = row[f];
        }
        if (minVal != maxVal) {
          splitFeature = f;
          foundVariance = true;
          break;
        }
      }
      // If all features have no variance, this is a leaf node
      if (!foundVariance) {
        return IsolationTree.leaf(size: X.length);
      }
    }

    // Randomly pick a split value between minVal and maxVal
    final double splitValue = minVal + random.nextDouble() * (maxVal - minVal);

    // Partition the dataset
    final List<List<double>> leftData = [];
    final List<List<double>> rightData = [];
    for (final row in X) {
      if (row[splitFeature] < splitValue) {
        leftData.add(row);
      } else {
        rightData.add(row);
      }
    }

    return IsolationTree.internal(
      left: _buildTree(leftData, currentHeight + 1, maxHeight),
      right: _buildTree(rightData, currentHeight + 1, maxHeight),
      splitFeature: splitFeature,
      splitValue: splitValue,
      size: X.length,
    );
  }

  /// Traverses a tree to compute the path length for instance [x].
  double _pathLength(List<double> x, IsolationTree tree, int currentDepth) {
    if (tree.isLeaf) {
      return currentDepth + _c(tree.size);
    }

    final int f = tree.splitFeature!;
    final double splitVal = tree.splitValue!;

    if (x[f] < splitVal) {
      return _pathLength(x, tree.left!, currentDepth + 1);
    } else {
      return _pathLength(x, tree.right!, currentDepth + 1);
    }
  }

  /// Average path length of unsuccessful searches in a Binary Search Tree of size [n].
  /// Represented mathematically as c(n).
  double _c(int n) {
    if (n <= 1) return 0.0;
    if (n == 2) return 1.0;
    const double eulerMascheroni = 0.5772156649;
    return 2.0 * (log(n - 1) + eulerMascheroni) - (2.0 * (n - 1) / n);
  }
}
