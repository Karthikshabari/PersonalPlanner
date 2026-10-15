#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <app_links/app_links_plugin_c_api.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Planner deep-link scheme; must equal PlannerUriScheme.value in Dart.
constexpr wchar_t kScheme[] = L"com.personalplanner.personalplanner";

// Windows only opens custom-scheme links if the scheme is registered. Register
// per user (no admin needed) on every launch so a moved or copied build keeps
// pointing at the current executable.
void RegisterUriScheme() {
  wchar_t exe[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, exe, MAX_PATH) == 0) return;
  std::wstring root = std::wstring(L"Software\\Classes\\") + kScheme;
  std::wstring protocol = std::wstring(L"URL:") + kScheme;
  std::wstring command = std::wstring(L"\"") + exe + L"\" \"%1\"";
  ::RegSetKeyValueW(HKEY_CURRENT_USER, root.c_str(), nullptr, REG_SZ,
                    protocol.c_str(),
                    static_cast<DWORD>((protocol.size() + 1) * sizeof(wchar_t)));
  ::RegSetKeyValueW(HKEY_CURRENT_USER, root.c_str(), L"URL Protocol", REG_SZ,
                    L"", sizeof(wchar_t));
  std::wstring open = root + L"\\shell\\open\\command";
  ::RegSetKeyValueW(HKEY_CURRENT_USER, open.c_str(), nullptr, REG_SZ,
                    command.c_str(),
                    static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  RegisterUriScheme();

  // A browser callback starts a second process. Hand its link to the running
  // planner and exit instead of opening another window.
  if (std::wstring(command_line).find(kScheme) != std::wstring::npos &&
      SendAppLinkToInstance()) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Personal Planner", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
