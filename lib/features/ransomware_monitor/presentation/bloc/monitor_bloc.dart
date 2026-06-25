import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ampcrypt/core/ml/isolation_forest.dart';
import '../../data/datasources/directory_watcher_service.dart';
import '../../data/models/sliding_window_features.dart';
import 'package:ampcrypt/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:ampcrypt/features/vault/presentation/bloc/vault_event.dart';
import 'package:ampcrypt/features/vault/domain/repositories/vault_repository.dart';
import 'monitor_event.dart';
import 'monitor_state.dart';

/// BLoC to handle Ransomware Monitoring logic, calibration, and alarm triggering.
class MonitorBloc extends Bloc<MonitorEvent, MonitorState> {
  final DirectoryWatcherService _watcherService;
  final VaultBloc _vaultBloc;
  final VaultRepository _vaultRepository;
  final IsolationForest _isolationForest;

  StreamSubscription<SlidingWindowFeatures>? _featuresSubscription;
  StreamSubscription<String>? _statusSubscription;

  /// Required number of normal activity samples (seconds) to calibrate.
  final int calibrationRequiredSamples = 30;
  final List<List<double>> _calibrationData = [];

  MonitorBloc({
    required this._watcherService,
    required this._vaultBloc,
    required this._vaultRepository,
  })  : _isolationForest = IsolationForest(numTrees: 100, subsampleSize: 256),
        super(const MonitorState()) {
    on<StartMonitoringEvent>(_onStartMonitoring);
    on<StopMonitoringEvent>(_onStopMonitoring);
    on<UpdateStatusEvent>(_onUpdateStatus);
    on<NewFeaturesProcessedEvent>(_onNewFeaturesProcessed);
    on<ResetMonitorAlarmEvent>(_onResetAlarm);
  }

  void _onStartMonitoring(StartMonitoringEvent event, Emitter<MonitorState> emit) {
    _calibrationData.clear();
    _featuresSubscription?.cancel();
    _statusSubscription?.cancel();

    _watcherService.startWatching(event.path);

    _statusSubscription = _watcherService.statusStream.listen((status) {
      add(UpdateStatusEvent(status));
    });

    _featuresSubscription = _watcherService.featuresStream.listen((features) {
      add(NewFeaturesProcessedEvent(features));
    });

    emit(MonitorState(
      isMonitoring: true,
      isCalibrating: true,
      calibrationProgress: 0.0,
      watchedPath: event.path,
      statusMessage: 'Calibrating system... Please perform normal tasks.',
    ));
  }

  void _onStopMonitoring(StopMonitoringEvent event, Emitter<MonitorState> emit) {
    _watcherService.stopWatching();
    _featuresSubscription?.cancel();
    _statusSubscription?.cancel();
    _calibrationData.clear();

    emit(const MonitorState(
      isMonitoring: false,
      isCalibrating: false,
      watchedPath: null,
      currentAnomalyScore: 0.0,
      isAlarmTriggered: false,
      statusMessage: 'Monitoring stopped.',
    ));
  }

  void _onUpdateStatus(UpdateStatusEvent event, Emitter<MonitorState> emit) {
    emit(state.copyWith(statusMessage: event.status));
  }

  void _onNewFeaturesProcessed(NewFeaturesProcessedEvent event, Emitter<MonitorState> emit) {
    if (!state.isMonitoring) return;

    final featuresList = List<SlidingWindowFeatures>.from(state.recentFeatures)..add(event.features);
    if (featuresList.length > 20) {
      featuresList.removeAt(0);
    }

    if (state.isCalibrating) {
      // 1. Calibration phase: collect baseline data
      _calibrationData.add(event.features.toDoubleList());
      final double progress = _calibrationData.length / calibrationRequiredSamples;

      if (_calibrationData.length >= calibrationRequiredSamples) {
        // Build Isolation Forest model once data is accumulated
        try {
          _isolationForest.fit(_calibrationData);
          emit(state.copyWith(
            isCalibrating: false,
            calibrationProgress: 1.0,
            recentFeatures: featuresList,
            statusMessage: 'Calibration complete. Monitoring active.',
          ));
        } catch (e) {
          emit(state.copyWith(
            statusMessage: 'Calibration failed during fitting: ${e.toString()}',
          ));
        }
      } else {
        emit(state.copyWith(
          calibrationProgress: progress,
          recentFeatures: featuresList,
          statusMessage: 'Calibrating: ${(_calibrationData.length)}/$calibrationRequiredSamples samples logged.',
        ));
      }
    } else {
      // 2. Monitoring phase: evaluate features
      final double score = _isolationForest.evaluate(event.features.toDoubleList());
      final scoreList = List<double>.from(state.recentScores)..add(score);
      if (scoreList.length > 20) {
        scoreList.removeAt(0);
      }

      bool triggerAlarm = state.isAlarmTriggered;
      String status = 'Monitoring active.';

      final threshold = _vaultRepository.monitorSensitivity;
      if (score >= threshold && !triggerAlarm) {
        triggerAlarm = true;
        status = 'ALERT: ANOMALOUS ACTIVITY DETECTED!';
        // Stop watching to prevent further alerts during alarm state
        _watcherService.stopWatching();
        // Lock the vault immediately to protect contents
        _vaultBloc.add(LockVaultEvent());
      }

      emit(state.copyWith(
        currentAnomalyScore: score,
        recentFeatures: featuresList,
        recentScores: scoreList,
        isAlarmTriggered: triggerAlarm,
        statusMessage: status,
      ));
    }
  }

  void _onResetAlarm(ResetMonitorAlarmEvent event, Emitter<MonitorState> emit) {
    if (state.watchedPath != null) {
      _watcherService.startWatching(state.watchedPath!);
    }
    emit(state.copyWith(
      isAlarmTriggered: false,
      currentAnomalyScore: 0.0,
      statusMessage: 'Alarm reset. Monitoring resumed.',
    ));
  }

  @override
  Future<void> close() {
    _featuresSubscription?.cancel();
    _statusSubscription?.cancel();
    _watcherService.dispose();
    return super.close();
  }
}
