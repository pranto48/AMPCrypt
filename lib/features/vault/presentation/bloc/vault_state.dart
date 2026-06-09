import 'package:equatable/equatable.dart';

abstract class VaultState extends Equatable {
  const VaultState();

  @override
  List<Object?> get props => [];
}

class VaultInitialState extends VaultState {}

class VaultUninitializedState extends VaultState {}

class VaultLockedState extends VaultState {}

class VaultLoadingState extends VaultState {
  final String message;

  const VaultLoadingState({this.message = 'Processing cryptographic operation...'});

  @override
  List<Object?> get props => [message];
}

class VaultUnlockedState extends VaultState {
  final String masterKeyHex;
  final List<String>? backupRecoveryPhrases;
  final Map<String, dynamic> deviceStatus;
  final int authLevel;

  const VaultUnlockedState({
    required this.masterKeyHex,
    this.backupRecoveryPhrases,
    required this.deviceStatus,
    this.authLevel = 4,
  });

  @override
  List<Object?> get props => [masterKeyHex, backupRecoveryPhrases, deviceStatus, authLevel];
}

class VaultFailureState extends VaultState {
  final String errorMessage;
  final VaultState previousState;

  const VaultFailureState({
    required this.errorMessage,
    required this.previousState,
  });

  @override
  List<Object?> get props => [errorMessage, previousState];
}
