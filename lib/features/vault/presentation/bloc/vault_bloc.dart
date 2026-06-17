import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/repositories/vault_repository.dart';
import 'vault_event.dart';
import 'vault_state.dart';

class VaultBloc extends Bloc<VaultEvent, VaultState> {
  final VaultRepository _vaultRepository;
  Timer? _autoLockTimer;

  VaultRepository get repository => _vaultRepository;

  VaultBloc({required VaultRepository vaultRepository})
      : _vaultRepository = vaultRepository,
        super(VaultInitialState()) {
    on<CheckVaultStatusEvent>(_onCheckVaultStatus);
    on<CreateVaultEvent>(_onCreateVault);
    on<UnlockVaultEvent>(_onUnlockVault);
    on<RecoverVaultEvent>(_onRecoverVault);
    on<LockVaultEvent>(_onLockVault);
    on<ResetToUninitializedEvent>(_onResetToUninitialized);
    on<UnlockWithMasterKeyEvent>(_onUnlockWithMasterKey);
  }

  void _onCheckVaultStatus(CheckVaultStatusEvent event, Emitter<VaultState> emit) {
    if (_vaultRepository.isVaultCreated) {
      emit(VaultLockedState());
    } else {
      emit(VaultUninitializedState());
    }
  }

  void _startAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      final minutes = _vaultRepository.autoLockMinutes;
      if (minutes > 0 && _vaultRepository.isUnlocked) {
        final lastActivity = _vaultRepository.lastActivityTime;
        if (lastActivity != null) {
          final idle = DateTime.now().difference(lastActivity);
          if (idle >= Duration(minutes: minutes)) {
            add(LockVaultEvent());
          }
        }
      }
    });
  }

  void _stopAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  Future<void> _onCreateVault(CreateVaultEvent event, Emitter<VaultState> emit) async {
    emit(const VaultLoadingState(message: 'Hashing password via Argon2id & creating SLIP-39 shares...'));
    try {
      final recoveryPhrases = await _vaultRepository.createVault(
        event.password,
        authLevel: event.authLevel,
      );
      final masterKey = _vaultRepository.masterKeyHex ?? '';
      final deviceStatus = await _vaultRepository.getDeviceStatus();
      
      _startAutoLockTimer();

      emit(VaultUnlockedState(
        masterKeyHex: masterKey,
        backupRecoveryPhrases: recoveryPhrases,
        deviceStatus: deviceStatus,
        authLevel: event.authLevel,
        webDavPort: _vaultRepository.webDavPort,
      ));
    } catch (e) {
      emit(VaultFailureState(
        errorMessage: 'Failed to create vault: ${e.toString()}',
        previousState: VaultUninitializedState(),
      ));
    }
  }

  Future<void> _onUnlockVault(UnlockVaultEvent event, Emitter<VaultState> emit) async {
    emit(const VaultLoadingState(message: 'Decrypting shares with derived Argon2id password key...'));
    try {
      final success = await _vaultRepository.unlockVault(event.password);
      if (success) {
        final masterKey = _vaultRepository.masterKeyHex ?? '';
        final deviceStatus = await _vaultRepository.getDeviceStatus();
        final authLevel = _vaultRepository.configuredAuthLevel;
        
        _startAutoLockTimer();

        emit(VaultUnlockedState(
          masterKeyHex: masterKey,
          deviceStatus: deviceStatus,
          authLevel: authLevel,
          webDavPort: _vaultRepository.webDavPort,
        ));
      } else {
        emit(VaultFailureState(
          errorMessage: 'Incorrect password or decryption failure.',
          previousState: VaultLockedState(),
        ));
      }
    } catch (e) {
      emit(VaultFailureState(
        errorMessage: 'An unexpected error occurred during unlock: ${e.toString()}',
        previousState: VaultLockedState(),
      ));
    }
  }

  Future<void> _onRecoverVault(RecoverVaultEvent event, Emitter<VaultState> emit) async {
    final previous = state;
    emit(const VaultLoadingState(message: 'Reconstructing Master Key from SLIP-39 recovery mnemonics...'));
    try {
      final success = await _vaultRepository.recoverVault(event.recoveryPhrases);
      if (success) {
        final masterKey = _vaultRepository.masterKeyHex ?? '';
        final deviceStatus = await _vaultRepository.getDeviceStatus();
        
        _startAutoLockTimer();

        emit(VaultUnlockedState(
          masterKeyHex: masterKey,
          deviceStatus: deviceStatus,
          webDavPort: _vaultRepository.webDavPort,
        ));
      } else {
        emit(VaultFailureState(
          errorMessage: 'Invalid recovery phrases or insufficient threshold. Please provide at least 2 correct phrases.',
          previousState: previous,
        ));
      }
    } catch (e) {
      emit(VaultFailureState(
        errorMessage: 'Recovery failed: ${e.toString()}',
        previousState: previous,
      ));
    }
  }

  void _onLockVault(LockVaultEvent event, Emitter<VaultState> emit) {
    _stopAutoLockTimer();
    _vaultRepository.lockVault();
    emit(VaultLockedState());
  }

  Future<void> _onResetToUninitialized(ResetToUninitializedEvent event, Emitter<VaultState> emit) async {
    _stopAutoLockTimer();
    _vaultRepository.lockVault();
    await _vaultRepository.clearVaultData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vault_created');
    await prefs.remove('auth_level');
    await prefs.remove('password_salt');
    await prefs.remove('encrypted_password_share');
    await prefs.remove('mock_fingerprint_share');
    await prefs.remove('mock_face_share');
    await prefs.remove('mock_voice_share');
    await prefs.remove('registered_face_embedding');
    await prefs.remove('registered_voice_embedding');
    emit(VaultUninitializedState());
  }

  Future<void> _onUnlockWithMasterKey(UnlockWithMasterKeyEvent event, Emitter<VaultState> emit) async {
    emit(const VaultLoadingState(message: 'Unlocking vault with recovered master key...'));
    try {
      final key = Uint8List.fromList(event.masterKey);
      final success = await _vaultRepository.unlockWithMasterKey(key);
      if (success) {
        final masterKeyHex = _vaultRepository.masterKeyHex ?? '';
        final deviceStatus = await _vaultRepository.getDeviceStatus();
        
        _startAutoLockTimer();

        emit(VaultUnlockedState(
          masterKeyHex: masterKeyHex,
          deviceStatus: deviceStatus,
          webDavPort: _vaultRepository.webDavPort,
        ));
      } else {
        emit(VaultFailureState(
          errorMessage: 'Failed to mount virtual drive with master key.',
          previousState: VaultLockedState(),
        ));
      }
    } catch (e) {
      emit(VaultFailureState(
        errorMessage: 'An unexpected error occurred during direct unlock: ${e.toString()}',
        previousState: VaultLockedState(),
      ));
    }
  }

  @override
  Future<void> close() {
    _stopAutoLockTimer();
    return super.close();
  }
}
