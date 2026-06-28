#include "flutter_window.h"

#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>

#include "winfsp_tpm_helper.h"
#include <wincrypt.h>
#include <shlobj.h>

// Helper to base64 encode
static std::string Base64Encode(const std::vector<uint8_t>& data) {
  DWORD dwSize = 0;
  CryptBinaryToStringA(data.data(), (DWORD)data.size(), CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &dwSize);
  std::string str(dwSize, '\0');
  CryptBinaryToStringA(data.data(), (DWORD)data.size(), CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, &str[0], &dwSize);
  if (!str.empty() && str.back() == '\0') str.pop_back();
  return str;
}

// Helper to base64 decode
static std::vector<uint8_t> Base64Decode(const std::string& str) {
  DWORD dwSize = 0;
  CryptStringToBinaryA(str.c_str(), (DWORD)str.size(), CRYPT_STRING_BASE64, nullptr, &dwSize, nullptr, nullptr);
  std::vector<uint8_t> data(dwSize);
  CryptStringToBinaryA(str.c_str(), (DWORD)str.size(), CRYPT_STRING_BASE64, data.data(), &dwSize, nullptr, nullptr);
  return data;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation during painting.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Setup method channel for Windows Hello native UserConsentVerifier and TPM KEK
  auto messenger = flutter_controller_->engine()->messenger();
  auto hello_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "ampcrypt/windows_hello",
      &flutter::StandardMethodCodec::GetInstance());

  HWND hwnd = flutter_controller_->view()->GetNativeWindow();

  hello_channel->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "authenticate") {
          std::thread([result]() {
            try {
              auto availability = winrt::Windows::Security::Credentials::UI::UserConsentVerifier::CheckAvailabilityAsync().get();
              if (availability == winrt::Windows::Security::Credentials::UI::UserConsentVerifierAvailability::Available) {
                auto verification_result = winrt::Windows::Security::Credentials::UI::UserConsentVerifier::RequestVerificationAsync(
                    L"Scan your face (Windows Hello) to validate your security factor share.")
                    .get();
                if (verification_result == winrt::Windows::Security::Credentials::UI::UserConsentVerificationResult::Verified) {
                  result->Success(flutter::EncodableValue(true));
                } else {
                  result->Success(flutter::EncodableValue(false));
                }
              } else {
                result->Error("UNAVAILABLE", "Windows Hello biometric verification is not available on this device.");
              }
            } catch (const winrt::hresult_error& ex) {
              std::wstring msg = ex.message().c_str();
              int size_needed = WideCharToMultiByte(CP_UTF8, 0, msg.data(), static_cast<int>(msg.size()), NULL, 0, NULL, NULL);
              std::string err_msg(size_needed, 0);
              WideCharToMultiByte(CP_UTF8, 0, msg.data(), static_cast<int>(msg.size()), &err_msg[0], size_needed, NULL, NULL);
              result->Error("WINRT_ERROR", err_msg);
            } catch (...) {
              result->Error("ERROR", "An unknown error occurred during Windows Hello verification.");
            }
          }).detach();
        } else if (call.method_name() == "isTpmSupported") {
          result->Success(flutter::EncodableValue(IsTpmSupported()));
        } else if (call.method_name() == "encryptKek") {
          const auto* args = std::get_if<std::vector<uint8_t>>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGUMENTS", "Expected raw KEK bytes.");
            return;
          }
          std::thread([result, rawKek = *args]() {
            auto cipher = EncryptKekWithTpm(rawKek);
            if (cipher.empty()) {
              result->Error("ENCRYPTION_FAILED", "Failed to encrypt KEK with TPM.");
            } else {
              result->Success(flutter::EncodableValue(Base64Encode(cipher)));
            }
          }).detach();
        } else if (call.method_name() == "decryptKek") {
          const auto* cipher_str = std::get_if<std::string>(call.arguments());
          if (!cipher_str) {
            result->Error("INVALID_ARGUMENTS", "Expected base64 cipher string.");
            return;
          }
          std::thread([result, cipher = *cipher_str, hwnd]() {
            auto rawKek = DecryptKekWithTpm(Base64Decode(cipher), hwnd);
            if (rawKek.empty()) {
              result->Error("DECRYPTION_FAILED", "Failed to decrypt KEK or Windows Hello verification canceled.");
            } else {
              result->Success(flutter::EncodableValue(rawKek));
            }
          }).detach();
        } else {
          result->NotImplemented();
        }
      });

  // Setup method channel for WinFsp Mounting
  auto winfsp_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "ampcrypt/winfsp",
      &flutter::StandardMethodCodec::GetInstance());

  winfsp_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "mount") {
          const auto* args_map = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args_map) {
            result->Error("INVALID_ARGUMENTS", "Expected map arguments.");
            return;
          }
          auto drive_it = args_map->find(flutter::EncodableValue("driveLetter"));
          auto port_it = args_map->find(flutter::EncodableValue("port"));
          if (drive_it == args_map->end() || port_it == args_map->end()) {
            result->Error("INVALID_ARGUMENTS", "Missing driveLetter or port.");
            return;
          }
          std::string drive = std::get<std::string>(drive_it->second);
          int port = std::get<int>(port_it->second);
          
          std::wstring wdrive(drive.begin(), drive.end());
          std::thread([result, wdrive, port]() {
            bool success = MountWinFspDrive(wdrive, port);
            result->Success(flutter::EncodableValue(success));
          }).detach();
        } else if (call.method_name() == "unmount") {
          const auto* drive_str = std::get_if<std::string>(call.arguments());
          if (!drive_str) {
            result->Error("INVALID_ARGUMENTS", "Expected drive letter string.");
            return;
          }
          std::wstring wdrive(drive_str->begin(), drive_str->end());
          std::thread([result, wdrive]() {
            bool success = UnmountWinFspDrive(wdrive);
            result->Success(flutter::EncodableValue(success));
          }).detach();
        } else if (call.method_name() == "getDiskSpace") {
          const auto* path_str = std::get_if<std::string>(call.arguments());
          if (!path_str) {
            result->Error("INVALID_ARGUMENTS", "Expected path string.");
            return;
          }
          std::wstring wpath(path_str->begin(), path_str->end());
          std::wstring rootPath = L"C:\\";
          bool isLetter0 = (wpath[0] >= L'A' && wpath[0] <= L'Z') || (wpath[0] >= L'a' && wpath[0] <= L'z');
          bool isLetter1 = wpath.length() >= 2 && ((wpath[1] >= L'A' && wpath[1] <= L'Z') || (wpath[1] >= L'a' && wpath[1] <= L'z'));
          
          if (wpath.length() >= 2 && isLetter0 && wpath[1] == L':') {
            rootPath = wpath.substr(0, 2) + L"\\";
          } else if (wpath.length() >= 3 && (wpath[0] == L'/' || wpath[0] == L'\\') && isLetter1 && wpath[2] == L':') {
            rootPath = wpath.substr(1, 2) + L"\\";
          }
          
          ULARGE_INTEGER freeBytesAvailable;
          ULARGE_INTEGER totalNumberOfBytes;
          ULARGE_INTEGER totalNumberOfFreeBytes;
          
          if (GetDiskFreeSpaceExW(rootPath.c_str(), &freeBytesAvailable, &totalNumberOfBytes, &totalNumberOfFreeBytes)) {
            flutter::EncodableMap resultMap;
            resultMap[flutter::EncodableValue("total")] = static_cast<int64_t>(totalNumberOfBytes.QuadPart);
            resultMap[flutter::EncodableValue("free")] = static_cast<int64_t>(freeBytesAvailable.QuadPart);
            result->Success(flutter::EncodableValue(resultMap));
          } else {
            result->Error("DISK_FREE_SPACE_FAILED", "Failed to get disk free space.");
          }
        } else if (call.method_name() == "refreshShell") {
          SHChangeNotify(0x08000000, 0, NULL, NULL); // SHCNE_ASSOCCHANGED
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
