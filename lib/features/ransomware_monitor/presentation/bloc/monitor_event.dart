/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'package:equatable/equatable.dart';
import '../../data/models/sliding_window_features.dart';

/// Base class for all Ransomware Monitor events.
abstract class MonitorEvent extends Equatable {
  const MonitorEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched to start monitoring a specific directory path.
class StartMonitoringEvent extends MonitorEvent {
  final String path;

  const StartMonitoringEvent(this.path);

  @override
  List<Object?> get props => [path];
}

/// Dispatched to stop monitoring the active directory.
class StopMonitoringEvent extends MonitorEvent {}

/// Dispatched to reset the triggered alarm state back to normal monitoring.
class ResetMonitorAlarmEvent extends MonitorEvent {}

/// Internal event: Dispatched when the file watcher service status updates.
class UpdateStatusEvent extends MonitorEvent {
  final String status;

  const UpdateStatusEvent(this.status);

  @override
  List<Object?> get props => [status];
}

/// Internal event: Dispatched when a new sliding feature window has been computed.
class NewFeaturesProcessedEvent extends MonitorEvent {
  final SlidingWindowFeatures features;

  const NewFeaturesProcessedEvent(this.features);

  @override
  List<Object?> get props => [features];
}
