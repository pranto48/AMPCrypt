#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Setup method channel for Windows Hello native UserConsentVerifier
  auto messenger = flutter_controller_->engine()->messenger();
  auto hello_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "ampcrypt/windows_hello",
      &flutter::StandardMethodCodec::GetInstance());

  hello_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "authenticate") {
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
            std::string err_msg(msg.begin(), msg.end());
            result->Error("WINRT_ERROR", err_msg);
          } catch (...) {
            result->Error("ERROR", "An unknown error occurred during Windows Hello verification.");
          }
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
