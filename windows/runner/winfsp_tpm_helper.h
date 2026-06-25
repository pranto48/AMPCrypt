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
