/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

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

class UnlockWithMasterKeyEvent extends VaultEvent {
  final List<int> masterKey;

  const UnlockWithMasterKeyEvent(this.masterKey);

  @override
  List<Object?> get props => [masterKey];
}

class RemoveVaultFromAppEvent extends VaultEvent {
  final String vaultPath;

  const RemoveVaultFromAppEvent(this.vaultPath);

  @override
  List<Object?> get props => [vaultPath];
}

class ForceDeleteVaultEvent extends VaultEvent {
  final String password;
  final String vaultPath;

  const ForceDeleteVaultEvent(this.password, this.vaultPath);

  @override
  List<Object?> get props => [password, vaultPath];
}
