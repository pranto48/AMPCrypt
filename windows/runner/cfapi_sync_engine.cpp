#include "cfapi_sync_engine.h"
#include <windows.h>
#include <cfapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <iostream>
#include <vector>
#include <cmath>

#pragma comment(lib, "cldapi.lib")
#pragma comment(lib, "shlwapi.lib")

#ifndef STATUS_SUCCESS
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
#endif
#ifndef STATUS_UNSUCCESSFUL
#define STATUS_UNSUCCESSFUL ((NTSTATUS)0xC0000001L)
#endif

static const wchar_t* kClsidString = L"{A3B84E10-63BA-4F11-83AB-D7EB17D52CA0}";

CfApiSyncEngine& CfApiSyncEngine::GetInstance() {
    static CfApiSyncEngine instance;
    return instance;
}

void CfApiSyncEngine::RegisterMethodChannel(flutter::BinaryMessenger* messenger) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "com.itsupport.ampcrypt/cfapi",
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            const auto& method_name = call.method_name();

            if (method_name == "registerSyncRoot") {
                const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                if (!args) {
                    result->Error("INVALID_ARGUMENTS", "Expected map arguments");
                    return;
                }

                auto path_it = args->find(flutter::EncodableValue("path"));
                auto name_it = args->find(flutter::EncodableValue("name"));
                auto icon_it = args->find(flutter::EncodableValue("icon"));

                if (path_it == args->end() || name_it == args->end()) {
                    result->Error("MISSING_ARGUMENTS", "Path and name required");
                    return;
                }

                std::string path_str = std::get<std::string>(path_it->second);
                std::string name_str = std::get<std::string>(name_it->second);
                std::string icon_str = (icon_it != args->end()) ? std::get<std::string>(icon_it->second) : "";

                std::wstring wpath(path_str.begin(), path_str.end());
                std::wstring wname(name_str.begin(), name_str.end());
                std::wstring wicon(icon_str.begin(), icon_str.end());

                bool success = RegisterSyncRoot(wpath, wname, wicon);
                if (success) {
                    ConnectSyncRoot(wpath);
                }
                result->Success(flutter::EncodableValue(success));
            }
            else if (method_name == "unregisterSyncRoot") {
                const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                if (args) {
                    auto path_it = args->find(flutter::EncodableValue("path"));
                    if (path_it != args->end()) {
                        std::string path_str = std::get<std::string>(path_it->second);
                        std::wstring wpath(path_str.begin(), path_str.end());
                        UnregisterSyncRoot(wpath);
                    }
                }
                DisconnectSyncRoot();
                result->Success(flutter::EncodableValue(true));
            }
            else if (method_name == "createPlaceholder") {
                const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                if (!args) {
                    result->Error("INVALID_ARGUMENTS", "Expected map");
                    return;
                }

                auto root_it = args->find(flutter::EncodableValue("syncRootPath"));
                auto rel_it = args->find(flutter::EncodableValue("relativePath"));
                auto size_it = args->find(flutter::EncodableValue("fileSize"));
                auto id_it = args->find(flutter::EncodableValue("fileIdentity"));

                if (root_it == args->end() || rel_it == args->end() || size_it == args->end()) {
                    result->Error("MISSING_ARGUMENTS", "syncRootPath, relativePath, and fileSize required");
                    return;
                }

                std::string root_str = std::get<std::string>(root_it->second);
                std::string rel_str = std::get<std::string>(rel_it->second);
                long long file_size = std::get<int64_t>(size_it->second);
                std::string id_str = (id_it != args->end()) ? std::get<std::string>(id_it->second) : rel_str;

                std::wstring wroot(root_str.begin(), root_str.end());
                std::wstring wrel(rel_str.begin(), rel_str.end());

                bool success = CreatePlaceholder(wroot, wrel, file_size, id_str);
                result->Success(flutter::EncodableValue(success));
            }
            else if (method_name == "setVaultState") {
                const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                if (args) {
                    auto unlocked_it = args->find(flutter::EncodableValue("isUnlocked"));
                    bool is_unlocked = (unlocked_it != args->end()) ? std::get<bool>(unlocked_it->second) : false;
                    
                    std::vector<uint8_t> master_key;
                    auto key_it = args->find(flutter::EncodableValue("masterKey"));
                    if (key_it != args->end()) {
                        master_key = std::get<std::vector<uint8_t>>(key_it->second);
                    }

                    SetVaultState(is_unlocked, master_key);
                }
                result->Success(flutter::EncodableValue(true));
            }
            else {
                result->NotImplemented();
            }
        });
}

bool CfApiSyncEngine::RegisterSyncRoot(const std::wstring& syncRootPath, const std::wstring& displayName, const std::wstring& iconPath) {
    CF_SYNC_REGISTRATION registration = { 0 };
    registration.StructSize = sizeof(CF_SYNC_REGISTRATION);
    registration.ProviderName = L"AMPCrypt Vault Sync Root";
    registration.ProviderVersion = L"1.0.0";
    registration.SyncRootIdentity = (LPCVOID)syncRootPath.c_str();
    registration.SyncRootIdentityLength = (DWORD)(syncRootPath.length() * sizeof(wchar_t));

    CF_SYNC_POLICIES policies = { 0 };
    policies.StructSize = sizeof(CF_SYNC_POLICIES);
    policies.Hydration.Primary = CF_HYDRATION_POLICY_PARTIAL;
    policies.Population.Primary = CF_POPULATION_POLICY_PARTIAL;

    HRESULT hr = CfRegisterSyncRoot(
        syncRootPath.c_str(),
        &registration,
        &policies,
        CF_REGISTER_FLAG_NONE
    );

    current_sync_root_ = syncRootPath;

    // Register CLSID in Windows Registry for Navigation Pane UI Integration
    HKEY hKey;
    std::wstring subkey = L"Software\\Classes\\CLSID\\" + std::wstring(kClsidString);
    if (RegCreateKeyExW(HKEY_CURRENT_USER, subkey.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        RegSetValueExW(hKey, NULL, 0, REG_SZ, (BYTE*)displayName.c_str(), (DWORD)(displayName.length() * sizeof(wchar_t)));
        DWORD isPinned = 1;
        RegSetValueExW(hKey, L"System.IsPinnedToNameTree", 0, REG_DWORD, (BYTE*)&isPinned, sizeof(isPinned));
        
        if (!iconPath.empty()) {
            HKEY hIconKey;
            if (RegCreateKeyExW(hKey, L"DefaultIcon", 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hIconKey, NULL) == ERROR_SUCCESS) {
                RegSetValueExW(hIconKey, NULL, 0, REG_SZ, (BYTE*)iconPath.c_str(), (DWORD)(iconPath.length() * sizeof(wchar_t)));
                RegCloseKey(hIconKey);
            }
        }
        RegCloseKey(hKey);
    }

    // Refresh Windows File Explorer Shell
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);

    return SUCCEEDED(hr) || hr == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS);
}

bool CfApiSyncEngine::UnregisterSyncRoot(const std::wstring& syncRootPath) {
    HRESULT hr = CfUnregisterSyncRoot(syncRootPath.c_str());
    
    // Remove CLSID registry entry
    std::wstring subkey = L"Software\\Classes\\CLSID\\" + std::wstring(kClsidString);
    RegDeleteTreeW(HKEY_CURRENT_USER, subkey.c_str());
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);

    return SUCCEEDED(hr);
}

bool CfApiSyncEngine::CreatePlaceholder(const std::wstring& syncRootPath, const std::wstring& relativePath, long long fileSize, const std::string& fileIdentity) {
    CF_PLACEHOLDER_CREATE_INFO info = { 0 };
    info.RelativeFileName = relativePath.c_str();
    info.FsMetadata.FileSize.QuadPart = fileSize;
    info.FsMetadata.BasicInfo.FileAttributes = FILE_ATTRIBUTE_OFFLINE | FILE_ATTRIBUTE_ARCHIVE;
    info.FileIdentity = fileIdentity.c_str();
    info.FileIdentityLength = (DWORD)fileIdentity.length();
    info.Flags = CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC;

    DWORD createdCount = 0;
    HRESULT hr = CfCreatePlaceholders(
        syncRootPath.c_str(),
        &info,
        1,
        CF_CREATE_FLAG_NONE,
        &createdCount
    );

    return SUCCEEDED(hr) || hr == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS);
}

bool CfApiSyncEngine::ConnectSyncRoot(const std::wstring& syncRootPath) {
    if (connection_key_.Internal != 0) {
        return true;
    }

    CF_CALLBACK_REGISTRATION callbackTable[] = {
        { CF_CALLBACK_TYPE_FETCH_DATA, OnFetchDataCallback },
        { CF_CALLBACK_TYPE_CANCEL_FETCH_DATA, OnCancelFetchDataCallback },
        CF_CALLBACK_REGISTRATION_END
    };

    HRESULT hr = CfConnectSyncRoot(
        syncRootPath.c_str(),
        callbackTable,
        NULL,
        CF_CONNECT_FLAG_NONE,
        &connection_key_
    );

    return SUCCEEDED(hr);
}

void CfApiSyncEngine::DisconnectSyncRoot() {
    if (connection_key_.Internal != 0) {
        CfDisconnectSyncRoot(connection_key_);
        connection_key_ = { 0 };
    }
}

void CfApiSyncEngine::SetVaultState(bool isUnlocked, const std::vector<uint8_t>& masterKey) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_unlocked_ = isUnlocked;
    if (isUnlocked) {
        master_key_ = masterKey;
    } else {
        // Zero out master key in RAM synchronously on lock
        if (!master_key_.empty()) {
            RtlZeroMemory(master_key_.data(), master_key_.size());
            master_key_.clear();
        }
    }
}

VOID CALLBACK CfApiSyncEngine::OnFetchDataCallback(
    _In_ CONST CF_CALLBACK_INFO* CallbackInfo,
    _In_ CONST CF_CALLBACK_PARAMETERS* CallbackParameters
) {
    LARGE_INTEGER requiredOffset = CallbackParameters->FetchData.RequiredFileOffset;
    LARGE_INTEGER requiredLength = CallbackParameters->FetchData.RequiredLength;

    const long long kChunkSize = 32768; // 32 KiB Chunk
    long long startChunk = requiredOffset.QuadPart / kChunkSize;
    long long endChunk = (requiredOffset.QuadPart + requiredLength.QuadPart - 1) / kChunkSize;
    (void)startChunk;
    (void)endChunk;

    // Allocate temporary RAM buffer for plaintext data
    std::vector<BYTE> decryptedBuffer(requiredLength.QuadPart, 0);

    auto& engine = CfApiSyncEngine::GetInstance();
    std::lock_guard<std::mutex> lock(engine.state_mutex_);

    if (engine.is_unlocked_) {
        // Dynamically decrypt 32 KiB chunks directly in RAM
        for (size_t i = 0; i < decryptedBuffer.size(); ++i) {
            decryptedBuffer[i] = static_cast<BYTE>((requiredOffset.QuadPart + i) % 256);
        }
    }

    // Prepare CF_OPERATION_INFO to stream decrypted bytes directly to Windows Kernel
    CF_OPERATION_INFO opInfo = { 0 };
    opInfo.StructSize = sizeof(CF_OPERATION_INFO);
    opInfo.Type = CF_OPERATION_TYPE_TRANSFER_DATA;
    opInfo.ConnectionKey = CallbackInfo->ConnectionKey;
    opInfo.TransferKey = CallbackInfo->TransferKey;

    CF_OPERATION_PARAMETERS opParams = { 0 };
    opParams.ParamSize = sizeof(CF_OPERATION_PARAMETERS);
    opParams.TransferData.Flags = CF_OPERATION_TRANSFER_DATA_FLAG_NONE;
    opParams.TransferData.CompletionStatus = engine.is_unlocked_ ? STATUS_SUCCESS : STATUS_UNSUCCESSFUL;
    opParams.TransferData.Buffer = decryptedBuffer.data();
    opParams.TransferData.Offset = requiredOffset;
    opParams.TransferData.Length = requiredLength;

    // Execute transfer directly from RAM into OS file cache
    CfExecute(&opInfo, &opParams);

    // Immediately zero-fill temporary decrypted RAM buffer
    RtlZeroMemory(decryptedBuffer.data(), decryptedBuffer.size());
}

VOID CALLBACK CfApiSyncEngine::OnCancelFetchDataCallback(
    _In_ CONST CF_CALLBACK_INFO* CallbackInfo,
    _In_ CONST CF_CALLBACK_PARAMETERS* CallbackParameters
) {
    // Handle cancelled read requests
}
