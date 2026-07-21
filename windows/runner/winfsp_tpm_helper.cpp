#include "winfsp_tpm_helper.h"
#include <winhttp.h>
#include <ncrypt.h>
#include <shlwapi.h>
#include <thread>
#include <mutex>
#include <iostream>

#include "winfsp/winfsp.h"

#pragma comment(lib, "ncrypt.lib")
#pragma comment(lib, "winhttp.lib")

#ifndef NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG
#define NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG 0x00000002
#endif

// ─── TPM & WINDOWS HELLO IMPLEMENTATION ─────────────────────────────────────

bool IsTpmSupported() {
    NCRYPT_PROV_HANDLE hProv = 0;
    SECURITY_STATUS status = NCryptOpenStorageProvider(&hProv, MS_PLATFORM_KEY_STORAGE_PROVIDER, 0);
    if (status == ERROR_SUCCESS) {
        NCryptFreeObject(hProv);
        return true;
    }
    return false;
}

SECURITY_STATUS GetOrCreateTpmKey(NCRYPT_PROV_HANDLE& hProv, NCRYPT_KEY_HANDLE& hKey) {
    SECURITY_STATUS status = NCryptOpenStorageProvider(&hProv, MS_PLATFORM_KEY_STORAGE_PROVIDER, 0);
    if (status != ERROR_SUCCESS) {
        // Fallback to software provider if TPM is not present
        status = NCryptOpenStorageProvider(&hProv, MS_KEY_STORAGE_PROVIDER, 0);
        if (status != ERROR_SUCCESS) return status;
    }

    status = NCryptOpenKey(hProv, &hKey, L"AMPCrypt_Vault_KEK", 0, 0);
    if (status != ERROR_SUCCESS) {
        // Create persistent key
        status = NCryptCreatePersistedKey(hProv, &hKey, BCRYPT_RSA_ALGORITHM, L"AMPCrypt_Vault_KEK", 0, 0);
        if (status != ERROR_SUCCESS) return status;

        // Force Windows Hello biometrics
        NCRYPT_UI_POLICY policy = {0};
        policy.dwVersion = 1;
        policy.dwFlags = NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG;
        policy.pszCreationTitle = L"AMPCrypt TPM Key Enrollment";
        policy.pszFriendlyName = L"AMPCrypt Vault Key Encryption Key";
        policy.pszDescription = L"Biometric verification required to lock/unlock your secure vault KEK.";

        status = NCryptSetProperty(hKey, NCRYPT_UI_POLICY_PROPERTY, (PBYTE)&policy, sizeof(policy), 0);

        status = NCryptFinalizeKey(hKey, 0);
    }
    return status;
}

std::vector<uint8_t> EncryptKekWithTpm(const std::vector<uint8_t>& rawKek) {
    NCRYPT_PROV_HANDLE hProv = 0;
    NCRYPT_KEY_HANDLE hKey = 0;
    SECURITY_STATUS status = GetOrCreateTpmKey(hProv, hKey);
    if (status != ERROR_SUCCESS) return {};

    DWORD cbResult = 0;
    status = NCryptEncrypt(hKey, (PBYTE)rawKek.data(), (DWORD)rawKek.size(), NULL, NULL, 0, &cbResult, NCRYPT_PAD_PKCS1_FLAG);
    if (status != ERROR_SUCCESS) {
        NCryptFreeObject(hKey);
        NCryptFreeObject(hProv);
        return {};
    }

    std::vector<uint8_t> encryptedKek(cbResult);
    status = NCryptEncrypt(hKey, (PBYTE)rawKek.data(), (DWORD)rawKek.size(), NULL, encryptedKek.data(), (DWORD)encryptedKek.size(), &cbResult, NCRYPT_PAD_PKCS1_FLAG);

    NCryptFreeObject(hKey);
    NCryptFreeObject(hProv);

    if (status != ERROR_SUCCESS) return {};
    return encryptedKek;
}

std::vector<uint8_t> DecryptKekWithTpm(const std::vector<uint8_t>& encryptedKek, HWND hwndParent) {
    NCRYPT_PROV_HANDLE hProv = 0;
    NCRYPT_KEY_HANDLE hKey = 0;
    SECURITY_STATUS status = GetOrCreateTpmKey(hProv, hKey);
    if (status != ERROR_SUCCESS) return {};

    if (hwndParent != NULL) {
        NCryptSetProperty(hKey, NCRYPT_WINDOW_HANDLE_PROPERTY, (PBYTE)&hwndParent, sizeof(hwndParent), 0);
    }

    DWORD cbResult = 0;
    status = NCryptDecrypt(hKey, (PBYTE)encryptedKek.data(), (DWORD)encryptedKek.size(), NULL, NULL, 0, &cbResult, NCRYPT_PAD_PKCS1_FLAG);
    if (status != ERROR_SUCCESS) {
        NCryptFreeObject(hKey);
        NCryptFreeObject(hProv);
        return {};
    }

    std::vector<uint8_t> decryptedKek(cbResult);
    status = NCryptDecrypt(hKey, (PBYTE)encryptedKek.data(), (DWORD)encryptedKek.size(), NULL, decryptedKek.data(), (DWORD)decryptedKek.size(), &cbResult, NCRYPT_PAD_PKCS1_FLAG);

    NCryptFreeObject(hKey);
    NCryptFreeObject(hProv);

    if (status != ERROR_SUCCESS) return {};
    return decryptedKek;
}

// ─── WINFSP MOUNTING IMPLEMENTATION ──────────────────────────────────────────

typedef NTSTATUS (*PFN_FspFileSystemCreate)(PWSTR DevicePath, const FSP_FSCTL_VOLUME_PARAMS *VolumeParams, const FSP_FILE_SYSTEM_INTERFACE *Interface, FSP_FILE_SYSTEM **PFileSystem);
typedef VOID (*PFN_FspFileSystemDelete)(FSP_FILE_SYSTEM *FileSystem);
typedef NTSTATUS (*PFN_FspFileSystemSetMountPoint)(FSP_FILE_SYSTEM *FileSystem, PWSTR MountPoint);
typedef VOID (*PFN_FspFileSystemRemoveMountPoint)(FSP_FILE_SYSTEM *FileSystem);
typedef NTSTATUS (*PFN_FspFileSystemStartDispatcher)(FSP_FILE_SYSTEM *FileSystem, ULONG ThreadCount);
typedef VOID (*PFN_FspFileSystemStopDispatcher)(FSP_FILE_SYSTEM *FileSystem);

static PFN_FspFileSystemCreate pfnFspFileSystemCreate = nullptr;
static PFN_FspFileSystemDelete pfnFspFileSystemDelete = nullptr;
static PFN_FspFileSystemSetMountPoint pfnFspFileSystemSetMountPoint = nullptr;
static PFN_FspFileSystemRemoveMountPoint pfnFspFileSystemRemoveMountPoint = nullptr;
static PFN_FspFileSystemStartDispatcher pfnFspFileSystemStartDispatcher = nullptr;
static PFN_FspFileSystemStopDispatcher pfnFspFileSystemStopDispatcher = nullptr;

static HMODULE hWinFspDll = nullptr;
static FSP_FILE_SYSTEM *g_FileSystem = nullptr;
static std::wstring g_DriveLetter;
static int g_WebDavPort = 0;
static std::thread g_DispatcherThread;
static std::wstring g_VaultRootPath; // e.g. L"E:\\"

bool LoadWinFsp() {
    if (hWinFspDll != nullptr) return true;

    HKEY hKey;
    wchar_t installDir[MAX_PATH] = L"";
    DWORD dwType = REG_SZ;
    DWORD dwSize = sizeof(installDir);
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WinFsp", 0, KEY_READ | KEY_WOW64_32KEY, &hKey) == ERROR_SUCCESS) {
        RegQueryValueExW(hKey, L"InstallDir", nullptr, &dwType, (LPBYTE)installDir, &dwSize);
        RegCloseKey(hKey);
    }

    std::wstring dllPath = installDir;
    if (dllPath.empty()) {
        dllPath = L"C:\\Program Files (x86)\\WinFsp\\";
    }
    dllPath += L"bin\\winfsp-x64.dll";

    hWinFspDll = LoadLibraryW(dllPath.c_str());
    if (hWinFspDll == nullptr) {
        hWinFspDll = LoadLibraryW(L"winfsp-x64.dll");
        if (hWinFspDll == nullptr) return false;
    }

    pfnFspFileSystemCreate = (PFN_FspFileSystemCreate)GetProcAddress(hWinFspDll, "FspFileSystemCreate");
    pfnFspFileSystemDelete = (PFN_FspFileSystemDelete)GetProcAddress(hWinFspDll, "FspFileSystemDelete");
    pfnFspFileSystemSetMountPoint = (PFN_FspFileSystemSetMountPoint)GetProcAddress(hWinFspDll, "FspFileSystemSetMountPoint");
    pfnFspFileSystemRemoveMountPoint = (PFN_FspFileSystemRemoveMountPoint)GetProcAddress(hWinFspDll, "FspFileSystemRemoveMountPoint");
    pfnFspFileSystemStartDispatcher = (PFN_FspFileSystemStartDispatcher)GetProcAddress(hWinFspDll, "FspFileSystemStartDispatcher");
    pfnFspFileSystemStopDispatcher = (PFN_FspFileSystemStopDispatcher)GetProcAddress(hWinFspDll, "FspFileSystemStopDispatcher");

    return (pfnFspFileSystemCreate && pfnFspFileSystemDelete && pfnFspFileSystemSetMountPoint && pfnFspFileSystemRemoveMountPoint && pfnFspFileSystemStartDispatcher && pfnFspFileSystemStopDispatcher);
}

// Minimal WinFsp file system interface implementation
// Forward requests to localhost WebDAV server via HTTP using WinHTTP

static NTSTATUS FspGetVolumeInfo(FSP_FILE_SYSTEM *FileSystem, FSP_FSCTL_VOLUME_INFO *VolumeInfo) {
    // Default fallback values
    UINT64 totalSize = 100ULL * 1024 * 1024 * 1024; // 100 GB
    UINT64 freeSize  =  50ULL * 1024 * 1024 * 1024; //  50 GB

    // Query real disk stats from the vault's host drive
    if (!g_VaultRootPath.empty()) {
        ULARGE_INTEGER freeBytesAvailable, totalBytes, totalFreeBytes;
        if (GetDiskFreeSpaceExW(g_VaultRootPath.c_str(),
                                &freeBytesAvailable,
                                &totalBytes,
                                &totalFreeBytes)) {
            totalSize = totalBytes.QuadPart;
            freeSize  = freeBytesAvailable.QuadPart;
        }
    }

    VolumeInfo->TotalSize = totalSize;
    VolumeInfo->FreeSize  = freeSize;
    VolumeInfo->VolumeLabelLength = 16;
    memcpy(VolumeInfo->VolumeLabel, L"AMPCrypt", 16);
    return STATUS_SUCCESS;
}

static NTSTATUS FspGetFileInfo(FSP_FILE_SYSTEM *FileSystem, PVOID FileContext, FSP_FSCTL_FILE_INFO *FileInfo) {
    HANDLE hFile = (HANDLE)FileContext;
    BY_HANDLE_FILE_INFORMATION info;
    if (!GetFileInformationByHandle(hFile, &info)) {
        return STATUS_UNSUCCESSFUL;
    }
    FileInfo->FileAttributes = info.dwFileAttributes;
    FileInfo->AllocationSize = ((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
    FileInfo->FileSize = FileInfo->AllocationSize;
    FileInfo->CreationTime = ((uint64_t)info.ftCreationTime.dwHighDateTime << 32) | info.ftCreationTime.dwLowDateTime;
    FileInfo->LastAccessTime = ((uint64_t)info.ftLastAccessTime.dwHighDateTime << 32) | info.ftLastAccessTime.dwLowDateTime;
    FileInfo->LastWriteTime = ((uint64_t)info.ftLastWriteTime.dwHighDateTime << 32) | info.ftLastWriteTime.dwLowDateTime;
    FileInfo->ChangeTime = FileInfo->LastWriteTime;
    FileInfo->IndexNumber = ((uint64_t)info.nFileIndexHigh << 32) | info.nFileIndexLow;
    return STATUS_SUCCESS;
}

std::wstring GetUncPath(PCWSTR FileName) {
    // Construct UNC path: \\localhost@port\DavWWWRoot\filename
    wchar_t portStr[16];
    swprintf_s(portStr, L"%d", g_WebDavPort);
    
    std::wstring path = L"\\\\localhost@";
    path += portStr;
    path += L"\\DavWWWRoot";
    if (FileName != nullptr && FileName[0] != L'\0') {
        if (FileName[0] != L'\\') path += L"\\";
        path += FileName;
    }
    return path;
}

static NTSTATUS FspOpen(FSP_FILE_SYSTEM *FileSystem, PWSTR FileName, UINT32 CreateOptions, UINT32 GrantedAccess, PVOID *PFileContext, FSP_FSCTL_FILE_INFO *FileInfo) {
    std::wstring uncPath = GetUncPath(FileName);
    HANDLE hFile = CreateFileW(uncPath.c_str(), GrantedAccess, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        if (err == ERROR_FILE_NOT_FOUND || err == ERROR_PATH_NOT_FOUND) return STATUS_OBJECT_NAME_NOT_FOUND;
        if (err == ERROR_ACCESS_DENIED) return STATUS_ACCESS_DENIED;
        return STATUS_UNSUCCESSFUL;
    }
    *PFileContext = (PVOID)hFile;
    return FspGetFileInfo(FileSystem, hFile, FileInfo);
}

static VOID FspClose(FSP_FILE_SYSTEM *FileSystem, PVOID FileContext) {
    HANDLE hFile = (HANDLE)FileContext;
    if (hFile != INVALID_HANDLE_VALUE && hFile != NULL) {
        CloseHandle(hFile);
    }
}

static NTSTATUS FspRead(FSP_FILE_SYSTEM *FileSystem, PVOID FileContext, PVOID Buffer, UINT64 Offset, ULONG Length, PULONG PBytesTransferred) {
    HANDLE hFile = (HANDLE)FileContext;
    OVERLAPPED ov = {0};
    ov.Offset = (DWORD)Offset;
    ov.OffsetHigh = (DWORD)(Offset >> 32);
    DWORD read = 0;
    if (!ReadFile(hFile, Buffer, Length, &read, &ov)) {
        DWORD err = GetLastError();
        if (err == ERROR_HANDLE_EOF) {
            *PBytesTransferred = 0;
            return STATUS_SUCCESS;
        }
        return STATUS_UNSUCCESSFUL;
    }
    *PBytesTransferred = read;
    return STATUS_SUCCESS;
}

static NTSTATUS FspWrite(FSP_FILE_SYSTEM *FileSystem, PVOID FileContext, PVOID Buffer, UINT64 Offset, ULONG Length, BOOLEAN WriteToEndOfFile, BOOLEAN ConstrainedIo, PULONG PBytesTransferred, FSP_FSCTL_FILE_INFO *FileInfo) {
    HANDLE hFile = (HANDLE)FileContext;
    OVERLAPPED ov = {0};
    ov.Offset = (DWORD)Offset;
    ov.OffsetHigh = (DWORD)(Offset >> 32);
    DWORD written = 0;
    if (!WriteFile(hFile, Buffer, Length, &written, &ov)) {
        return STATUS_UNSUCCESSFUL;
    }
    *PBytesTransferred = written;
    return FspGetFileInfo(FileSystem, FileContext, FileInfo);
}

static NTSTATUS FspCreate(FSP_FILE_SYSTEM *FileSystem, PWSTR FileName, UINT32 CreateOptions, UINT32 GrantedAccess, UINT32 FileAttributes, PSECURITY_DESCRIPTOR SecurityDescriptor, UINT64 AllocationSize, PVOID *PFileContext, FSP_FSCTL_FILE_INFO *FileInfo) {
    std::wstring uncPath = GetUncPath(FileName);
    DWORD dwCreation = CREATE_NEW;
    DWORD dwFlags = FILE_ATTRIBUTE_NORMAL;
    if (CreateOptions & FILE_DIRECTORY_FILE) {
        if (!CreateDirectoryW(uncPath.c_str(), NULL)) {
            DWORD err = GetLastError();
            if (err == ERROR_ALREADY_EXISTS) return STATUS_OBJECT_NAME_COLLISION;
            return STATUS_UNSUCCESSFUL;
        }
        dwCreation = OPEN_EXISTING;
        dwFlags = FILE_FLAG_BACKUP_SEMANTICS;
    }
    
    HANDLE hFile = CreateFileW(uncPath.c_str(), GrantedAccess, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, dwCreation, dwFlags, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        if (err == ERROR_ALREADY_EXISTS) return STATUS_OBJECT_NAME_COLLISION;
        return STATUS_UNSUCCESSFUL;
    }
    *PFileContext = (PVOID)hFile;
    return FspGetFileInfo(FileSystem, hFile, FileInfo);
}

static VOID FspCleanup(FSP_FILE_SYSTEM *FileSystem, PVOID FileContext, PWSTR FileName, ULONG Flags) {
    HANDLE hFile = (HANDLE)FileContext;
    if (Flags & FspCleanupDelete) {
        CloseHandle(hFile);
        std::wstring uncPath = GetUncPath(FileName);
        DeleteFileW(uncPath.c_str());
    }
}

static NTSTATUS FspReadDirectory(FSP_FILE_SYSTEM *FileSystem, PVOID FileContext, PWSTR Pattern, PWSTR Marker, PVOID Buffer, ULONG Length, PULONG PBytesTransferred) {
    *PBytesTransferred = 0;
    return STATUS_SUCCESS;
}

static FSP_FILE_SYSTEM_INTERFACE g_Interface;
static std::once_flag g_InterfaceInitOnce;

void InitializeFspInterface() {
    std::call_once(g_InterfaceInitOnce, []() {
        memset(&g_Interface, 0, sizeof(g_Interface));
        g_Interface.GetVolumeInfo = FspGetVolumeInfo;
        g_Interface.GetFileInfo = FspGetFileInfo;
        g_Interface.Open = FspOpen;
        g_Interface.Create = FspCreate;
        g_Interface.Close = FspClose;
        g_Interface.Cleanup = FspCleanup;
        g_Interface.Read = FspRead;
        g_Interface.Write = FspWrite;
        g_Interface.ReadDirectory = FspReadDirectory;
    });
}

bool MountWinFspDrive(const std::wstring& driveLetter, int webDavPort) {
    if (!LoadWinFsp()) return false;
    if (g_FileSystem != nullptr) return false;

    InitializeFspInterface();

    g_DriveLetter = driveLetter;
    g_WebDavPort = webDavPort;

    // Create virtual disk
    FSP_FSCTL_VOLUME_PARAMS params;
    memset(&params, 0, sizeof(params));
    params.Version = sizeof(params);
    params.SectorSize = 512;
    params.SectorsPerAllocationUnit = 1;
    params.MaxComponentLength = 255;
    params.VolumeSerialNumber = 0x87654321;
    params.VolumeCreationTime = 0;
    
    // Set filesystem name
    wcscpy_s(params.FileSystemName, sizeof(params.FileSystemName) / sizeof(wchar_t), L"NTFS");

    NTSTATUS status = pfnFspFileSystemCreate((PWSTR)FSP_FSCTL_DISK_DEVICE_NAME, &params, &g_Interface, &g_FileSystem);
    if (status != STATUS_SUCCESS) {
        g_FileSystem = nullptr;
        return false;
    }

    status = pfnFspFileSystemSetMountPoint(g_FileSystem, (PWSTR)driveLetter.c_str());
    if (status != STATUS_SUCCESS) {
        pfnFspFileSystemDelete(g_FileSystem);
        g_FileSystem = nullptr;
        return false;
    }

    status = pfnFspFileSystemStartDispatcher(g_FileSystem, 0);
    if (status != STATUS_SUCCESS) {
        pfnFspFileSystemRemoveMountPoint(g_FileSystem);
        pfnFspFileSystemDelete(g_FileSystem);
        g_FileSystem = nullptr;
        return false;
    }

    return true;
}

bool UnmountWinFspDrive(const std::wstring& driveLetter) {
    if (g_FileSystem == nullptr) return false;
    if (!LoadWinFsp()) return false;

    pfnFspFileSystemStopDispatcher(g_FileSystem);
    pfnFspFileSystemRemoveMountPoint(g_FileSystem);
    pfnFspFileSystemDelete(g_FileSystem);
    g_FileSystem = nullptr;
    g_VaultRootPath.clear();
    return true;
}

void SetVaultRootPath(const std::wstring& rootPath) {
    g_VaultRootPath = rootPath;
}
