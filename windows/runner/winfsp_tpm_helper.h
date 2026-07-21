#pragma once

#include <vector>
#include <string>
#include <windows.h>

// TPM & Windows Hello Helper Functions
bool IsTpmSupported();
std::vector<uint8_t> EncryptKekWithTpm(const std::vector<uint8_t>& rawKek);
std::vector<uint8_t> DecryptKekWithTpm(const std::vector<uint8_t>& encryptedKek, HWND hwndParent);

// WinFsp Mount Helper Functions
bool MountWinFspDrive(const std::wstring& driveLetter, int webDavPort);
bool UnmountWinFspDrive(const std::wstring& driveLetter);

/// Sets the vault root path used to query real disk statistics (e.g., L"E:\\").
/// Call this before or after MountWinFspDrive.
void SetVaultRootPath(const std::wstring& rootPath);
