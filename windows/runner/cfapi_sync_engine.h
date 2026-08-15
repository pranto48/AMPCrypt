#pragma once

#include <windows.h>
#include <cfapi.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

class CfApiSyncEngine {
public:
    static CfApiSyncEngine& GetInstance();

    // Method channel registration for Flutter
    void RegisterMethodChannel(flutter::BinaryMessenger* messenger);

    // 1. Sync Root Registration & Explorer Navigation Pane UI Setup
    bool RegisterSyncRoot(const std::wstring& syncRootPath, const std::wstring& displayName, const std::wstring& iconPath);
    bool UnregisterSyncRoot(const std::wstring& syncRootPath);

    // 2. Placeholder File Creation (0-byte dehydrated metadata entries)
    bool CreatePlaceholder(const std::wstring& syncRootPath, const std::wstring& relativePath, long long fileSize, const std::string& fileIdentity);

    // 3. Connect Sync Root & Start Hydration Callback Handlers
    bool ConnectSyncRoot(const std::wstring& syncRootPath);
    void DisconnectSyncRoot();

    // 4. Vault State Management (Locked/Unlocked)
    void SetVaultState(bool isUnlocked, const std::vector<uint8_t>& masterKey);

private:
    CfApiSyncEngine() = default;
    ~CfApiSyncEngine() = default;

    static VOID CALLBACK OnFetchDataCallback(
        _In_ CONST CF_CALLBACK_INFO* CallbackInfo,
        _In_ CONST CF_CALLBACK_PARAMETERS* CallbackParameters
    );

    static VOID CALLBACK OnCancelFetchDataCallback(
        _In_ CONST CF_CALLBACK_INFO* CallbackInfo,
        _In_ CONST CF_CALLBACK_PARAMETERS* CallbackParameters
    );

    CF_CONNECTION_KEY connection_key_ = CF_CONNECTION_KEY_INVALID;
    std::wstring current_sync_root_;
    bool is_unlocked_ = false;
    std::vector<uint8_t> master_key_;
    std::mutex state_mutex_;
};
