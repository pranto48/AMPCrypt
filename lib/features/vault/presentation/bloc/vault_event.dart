import 'package:equatable/equatable.dart';

abstract class VaultEvent extends Equatable {
  const VaultEvent();

  @override
  List<Object?> get props => [];
}

class CheckVaultStatusEvent extends VaultEvent {}

class CreateVaultEvent extends VaultEvent {
  final String password;
  final int authLevel;

  const CreateVaultEvent(this.password, {this.authLevel = 4});

  @override
  List<Object?> get props => [password, authLevel];
}

class UnlockVaultEvent extends VaultEvent {
  final String password;

  const UnlockVaultEvent(this.password);

  @override
  List<Object?> get props => [password];
}

class RecoverVaultEvent extends VaultEvent {
  final List<String> recoveryPhrases;

  const RecoverVaultEvent(this.recoveryPhrases);

  @override
  List<Object?> get props => [recoveryPhrases];
}

class LockVaultEvent extends VaultEvent {}

class ResetToUninitializedEvent extends VaultEvent {}
