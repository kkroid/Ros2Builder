#include <Windows.h>
#include <commdlg.h>
#include <d3d11.h>
#include <mmsystem.h>
#include <shellapi.h>
#include <tchar.h>

#include <array>
#include <cstdio>
#include <cstring>
#include <string>

#include "audio_capturer.h"
#include "imgui.h"
#include "imgui_impl_dx11.h"
#include "imgui_impl_win32.h"
#include "ros_bridge.h"

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

namespace {

ID3D11Device *g_pd3d_device = nullptr;
ID3D11DeviceContext *g_pd3d_device_context = nullptr;
IDXGISwapChain *g_swap_chain = nullptr;
ID3D11RenderTargetView *g_main_render_target_view = nullptr;

void create_render_target() {
  ID3D11Texture2D *back_buffer = nullptr;
  g_swap_chain->GetBuffer(0, IID_PPV_ARGS(&back_buffer));
  g_pd3d_device->CreateRenderTargetView(back_buffer, nullptr, &g_main_render_target_view);
  back_buffer->Release();
}

void cleanup_render_target() {
  if (g_main_render_target_view) {
    g_main_render_target_view->Release();
    g_main_render_target_view = nullptr;
  }
}

bool create_device_d3d(HWND hwnd) {
  DXGI_SWAP_CHAIN_DESC swap_chain_desc = {};
  swap_chain_desc.BufferCount = 2;
  swap_chain_desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  swap_chain_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  swap_chain_desc.OutputWindow = hwnd;
  swap_chain_desc.SampleDesc.Count = 1;
  swap_chain_desc.Windowed = TRUE;
  swap_chain_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
  UINT create_device_flags = 0;
  D3D_FEATURE_LEVEL feature_level;
  const D3D_FEATURE_LEVEL feature_level_array[2] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0};
  HRESULT result = D3D11CreateDeviceAndSwapChain(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, create_device_flags, feature_level_array, 2,
      D3D11_SDK_VERSION, &swap_chain_desc, &g_swap_chain, &g_pd3d_device, &feature_level,
      &g_pd3d_device_context);
  if (result == DXGI_ERROR_UNSUPPORTED) {
    result = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_WARP, nullptr, create_device_flags, feature_level_array, 2,
        D3D11_SDK_VERSION, &swap_chain_desc, &g_swap_chain, &g_pd3d_device, &feature_level,
        &g_pd3d_device_context);
  }
  if (result != S_OK) {
    return false;
  }
  create_render_target();
  return true;
}

void cleanup_device_d3d() {
  cleanup_render_target();
  if (g_swap_chain) {
    g_swap_chain->Release();
    g_swap_chain = nullptr;
  }
  if (g_pd3d_device_context) {
    g_pd3d_device_context->Release();
    g_pd3d_device_context = nullptr;
  }
  if (g_pd3d_device) {
    g_pd3d_device->Release();
    g_pd3d_device = nullptr;
  }
}

LRESULT WINAPI wnd_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (ImGui_ImplWin32_WndProcHandler(hwnd, msg, wparam, lparam)) {
    return true;
  }
  switch (msg) {
    case WM_SIZE:
      if (g_pd3d_device != nullptr && wparam != SIZE_MINIMIZED) {
        cleanup_render_target();
        g_swap_chain->ResizeBuffers(0, static_cast<UINT>(LOWORD(lparam)), static_cast<UINT>(HIWORD(lparam)), DXGI_FORMAT_UNKNOWN, 0);
        create_render_target();
      }
      return 0;
    case WM_SYSCOMMAND:
      if ((wparam & 0xfff0) == SC_KEYMENU) {
        return 0;
      }
      break;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

void prepend_path(const std::string &path) {
  DWORD size = GetEnvironmentVariableA("PATH", nullptr, 0);
  std::string current(size, '\0');
  if (size > 0) {
    GetEnvironmentVariableA("PATH", current.data(), size);
    if (!current.empty() && current.back() == '\0') {
      current.pop_back();
    }
  }
  std::string next = path + ";" + current;
  SetEnvironmentVariableA("PATH", next.c_str());
  _putenv_s("PATH", next.c_str());
}

void apply_ros2_dist_environment() {
  std::string dist = ROS2_DIST_PATH;
  SetEnvironmentVariableA("AMENT_PREFIX_PATH", dist.c_str());
  _putenv_s("AMENT_PREFIX_PATH", dist.c_str());
  prepend_path(dist + "/bin");
}

bool browse_wav_file(char *buffer, DWORD buffer_size) {
  OPENFILENAMEA dialog = {};
  dialog.lStructSize = sizeof(dialog);
  dialog.lpstrFile = buffer;
  dialog.nMaxFile = buffer_size;
  dialog.lpstrFilter = "WAV files\0*.wav\0All files\0*.*\0";
  dialog.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;
  return GetOpenFileNameA(&dialog) == TRUE;
}

template <size_t Size>
void copy_to_buffer(std::array<char, Size> &buffer, const std::string &value) {
  std::snprintf(buffer.data(), buffer.size(), "%s", value.c_str());
}

std::string wide_to_utf8(const std::wstring &value) {
  if (value.empty()) {
    return {};
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}

struct CliOptions {
  bool auto_start = false;
  int domain_id = 0;
  std::string discovery_server;
  std::string audio_file;
  double send_speed = 20.0;
};

CliOptions parse_cli() {
  CliOptions options;
  int argc = 0;
  LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  for (int i = 1; i < argc; ++i) {
    std::wstring arg = argv[i];
    auto next = [&]() -> std::wstring {
      if (i + 1 >= argc) {
        return L"";
      }
      return argv[++i];
    };
    if (arg == L"--auto-start") {
      options.auto_start = true;
    } else if (arg == L"--domain-id") {
      options.domain_id = std::stoi(next());
    } else if (arg == L"--discovery-server") {
      std::wstring value = next();
      options.discovery_server = wide_to_utf8(value);
    } else if (arg == L"--audio-file") {
      std::wstring value = next();
      options.audio_file = wide_to_utf8(value);
    } else if (arg == L"--send-speed") {
      options.send_speed = std::stod(next());
    }
  }
  if (argv) {
    LocalFree(argv);
  }
  return options;
}

}  // namespace

int APIENTRY WinMain(HINSTANCE instance, HINSTANCE, LPSTR, int) {
  apply_ros2_dist_environment();
  CliOptions cli = parse_cli();

  WNDCLASSEXW window_class = {sizeof(window_class), CS_CLASSDC, wnd_proc, 0L, 0L,
                              instance, nullptr, nullptr, nullptr, nullptr,
                              L"Ros2BuilderWindowsDemo", nullptr};
  RegisterClassExW(&window_class);
  HWND hwnd = CreateWindowW(window_class.lpszClassName, L"Ros2Builder Windows ROS 2 Demo",
                            WS_OVERLAPPEDWINDOW, 100, 100, 1120, 760, nullptr, nullptr,
                            window_class.hInstance, nullptr);
  if (!create_device_d3d(hwnd)) {
    cleanup_device_d3d();
    UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
    return 1;
  }

  ShowWindow(hwnd, SW_SHOWDEFAULT);
  UpdateWindow(hwnd);

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO &io = ImGui::GetIO();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
  ImGui::StyleColorsLight();
  ImGui_ImplWin32_Init(hwnd);
  ImGui_ImplDX11_Init(g_pd3d_device, g_pd3d_device_context);

  RosBridge bridge;
  AudioCapturer audio_capturer;
  int domain_id = cli.domain_id;
  std::array<char, 128> node_name = {};
  std::array<char, 128> discovery_server = {};
  std::array<char, 256> command = {};
  std::array<char, MAX_PATH> audio_file = {};
  copy_to_buffer(node_name, "windows_ros2_demo");
  copy_to_buffer(discovery_server, cli.discovery_server);
  copy_to_buffer(audio_file, cli.audio_file);
  float publish_rate = 1.0f;
  float send_speed = static_cast<float>(cli.send_speed);
  float mic_duration = 5.0f;
  int qos_index = 0;

  if (cli.auto_start) {
    RuntimeConfig config;
    config.domain_id = domain_id;
    config.node_name = node_name.data();
    config.publish_rate_hz = publish_rate;
    config.qos_mode = qos_index == 0 ? "reliable" : "best_effort";
    config.discovery_server = discovery_server.data();
    bridge.start(config);
    if (audio_file[0] != '\0') {
      bridge.send_wav_file(audio_file.data(), send_speed);
    }
  }

  bool done = false;
  while (!done) {
    MSG message;
    while (PeekMessage(&message, nullptr, 0U, 0U, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessage(&message);
      if (message.message == WM_QUIT) {
        done = true;
      }
    }
    if (done) {
      break;
    }

    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(io.DisplaySize, ImGuiCond_Always);
    ImGui::Begin("Ros2Builder", nullptr,
                 ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize);

    ImGui::BeginGroup();
    ImGui::TextUnformatted("Runtime");
    ImGui::InputInt("Domain ID", &domain_id);
    ImGui::InputText("Node", node_name.data(), node_name.size());
    ImGui::SliderFloat("Publish Rate", &publish_rate, 0.2f, 20.0f, "%.1f Hz");
    ImGui::Combo("QoS", &qos_index, "reliable\0best_effort\0");
    ImGui::InputText("Discovery", discovery_server.data(), discovery_server.size());
    if (!bridge.is_running()) {
      if (ImGui::Button("Start", ImVec2(96, 0))) {
        RuntimeConfig config;
        config.domain_id = domain_id;
        config.node_name = node_name.data();
        config.publish_rate_hz = publish_rate;
        config.qos_mode = qos_index == 0 ? "reliable" : "best_effort";
        config.discovery_server = discovery_server.data();
        bridge.start(config);
      }
    } else if (ImGui::Button("Stop", ImVec2(96, 0))) {
      bridge.stop();
    }

    ImGui::Spacing();
    ImGui::TextUnformatted("Command");
    ImGui::InputText("##command", command.data(), command.size());
    ImGui::SameLine();
    if (ImGui::Button("Send") && command[0] != '\0') {
      bridge.send_command(command.data());
    }

    ImGui::Spacing();
    ImGui::TextUnformatted("Audio TX");
    ImGui::InputText("WAV", audio_file.data(), audio_file.size());
    ImGui::SameLine();
    if (ImGui::Button("Browse")) {
      browse_wav_file(audio_file.data(), static_cast<DWORD>(audio_file.size()));
    }
    ImGui::SliderFloat("Send Speed", &send_speed, 1.0f, 32.0f, "%.1fx");
    if (ImGui::Button("Send WAV") && audio_file[0] != '\0') {
      bridge.send_wav_file(audio_file.data(), send_speed);
    }
    ImGui::SameLine();
    if (ImGui::Button("Cancel TX")) {
      bridge.cancel_audio_tx();
    }

    ImGui::Spacing();
    ImGui::TextUnformatted("Audio RX");
    std::string latest_audio = bridge.latest_received_path();
    ImGui::TextWrapped("%s", latest_audio.empty() ? "" : latest_audio.c_str());
    if (ImGui::Button("Play Received") && !latest_audio.empty()) {
      PlaySoundA(latest_audio.c_str(), nullptr, SND_FILENAME | SND_ASYNC);
    }
    ImGui::Spacing();
    ImGui::TextUnformatted("Mic TX");
    ImGui::SliderFloat("Duration", &mic_duration, 1.0f, 30.0f, "%.1f s");
    if (!audio_capturer.is_running()) {
      if (ImGui::Button("Record & Send")) {
        audio_capturer.start(bridge, mic_duration);
      }
    } else if (ImGui::Button("Stop Mic")) {
      audio_capturer.stop();
    }
    std::string capture_error = audio_capturer.last_error();
    if (!capture_error.empty()) {
      ImGui::TextWrapped("%s", capture_error.c_str());
    }
    ImGui::EndGroup();

    ImGui::SameLine();
    ImGui::BeginGroup();
    ImGui::TextUnformatted("Status");
    ImGui::BeginChild("status_json", ImVec2(0, -1), true, ImGuiWindowFlags_HorizontalScrollbar);
    std::string snapshot = bridge.snapshot_json();
    ImGui::TextUnformatted(snapshot.c_str());
    ImGui::EndChild();
    ImGui::EndGroup();

    ImGui::End();

    ImGui::Render();
    const float clear_color[4] = {0.94f, 0.94f, 0.92f, 1.0f};
    g_pd3d_device_context->OMSetRenderTargets(1, &g_main_render_target_view, nullptr);
    g_pd3d_device_context->ClearRenderTargetView(g_main_render_target_view, clear_color);
    ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());
    g_swap_chain->Present(1, 0);
  }

  audio_capturer.stop();
  bridge.stop();
  ImGui_ImplDX11_Shutdown();
  ImGui_ImplWin32_Shutdown();
  ImGui::DestroyContext();
  cleanup_device_d3d();
  DestroyWindow(hwnd);
  UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
  return 0;
}