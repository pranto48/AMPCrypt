/// A data model representing the feature vector extracted from a sliding window
/// of file system events. These 5 features are fed into the Isolation Forest
/// for unsupervised anomaly detection.
class SlidingWindowFeatures {
  /// Write/creation operations per second in this window.
  final double writeRate;

  /// Deletion operations per second in this window.
  final double deleteRate;

  /// Rename/move operations per second in this window.
  final double renameRate;

  /// Ratio of events involving suspicious or high-entropy file extensions.
  final double extensionEntropy;

  /// Average change in file size (in kilobytes) for modifications.
  final double sizeDifference;

  SlidingWindowFeatures({
    required this.writeRate,
    required this.deleteRate,
    required this.renameRate,
    required this.extensionEntropy,
    required this.sizeDifference,
  });

  /// Converts the features to a list of doubles for ML model input.
  List<double> toDoubleList() {
    return [
      writeRate,
      deleteRate,
      renameRate,
      extensionEntropy,
      sizeDifference,
    ];
  }

  @override
  String toString() {
    return 'SlidingWindowFeatures(writeRate: ${writeRate.toStringAsFixed(2)}, '
        'deleteRate: ${deleteRate.toStringAsFixed(2)}, '
        'renameRate: ${renameRate.toStringAsFixed(2)}, '
        'extensionEntropy: ${extensionEntropy.toStringAsFixed(2)}, '
        'sizeDifference: ${sizeDifference.toStringAsFixed(2)})';
  }
}
