import 'package:equatable/equatable.dart';
import '../../data/models/sliding_window_features.dart';

/// Represents the state of the Ransomware Monitor.
class MonitorState extends Equatable {
  final bool isMonitoring;
  final bool isCalibrating;
  final double calibrationProgress; // Range: 0.0 to 1.0
  final String? watchedPath;
  final double currentAnomalyScore;
  final bool isAlarmTriggered;
  final String statusMessage;
  final List<SlidingWindowFeatures> recentFeatures;
  final List<double> recentScores;

  const MonitorState({
    this.isMonitoring = false,
    this.isCalibrating = false,
    this.calibrationProgress = 0.0,
    this.watchedPath,
    this.currentAnomalyScore = 0.0,
    this.isAlarmTriggered = false,
    this.statusMessage = 'System inactive',
    this.recentFeatures = const [],
    this.recentScores = const [],
  });

  MonitorState copyWith({
    bool? isMonitoring,
    bool? isCalibrating,
    double? calibrationProgress,
    String? watchedPath,
    double? currentAnomalyScore,
    bool? isAlarmTriggered,
    String? statusMessage,
    List<SlidingWindowFeatures>? recentFeatures,
    List<double>? recentScores,
  }) {
    return MonitorState(
      isMonitoring: isMonitoring ?? this.isMonitoring,
      isCalibrating: isCalibrating ?? this.isCalibrating,
      calibrationProgress: calibrationProgress ?? this.calibrationProgress,
      watchedPath: watchedPath ?? this.watchedPath,
      currentAnomalyScore: currentAnomalyScore ?? this.currentAnomalyScore,
      isAlarmTriggered: isAlarmTriggered ?? this.isAlarmTriggered,
      statusMessage: statusMessage ?? this.statusMessage,
      recentFeatures: recentFeatures ?? this.recentFeatures,
      recentScores: recentScores ?? this.recentScores,
    );
  }

  @override
  List<Object?> get props => [
        isMonitoring,
        isCalibrating,
        calibrationProgress,
        watchedPath,
        currentAnomalyScore,
        isAlarmTriggered,
        statusMessage,
        recentFeatures,
        recentScores,
      ];
}
