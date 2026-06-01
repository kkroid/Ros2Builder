#include "audio_capturer.h"

#include "ros_bridge.h"

#include <Windows.h>
#include <audioclient.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

namespace {

template <typename T>
void safe_release(T *&value) {
  if (value != nullptr) {
    value->Release();
    value = nullptr;
  }
}

std::string hresult_message(const char *prefix, HRESULT result) {
  char buffer[160] = {};
  std::snprintf(buffer, sizeof(buffer), "%s (HRESULT 0x%08lx)", prefix, static_cast<unsigned long>(result));
  return buffer;
}

bool is_extensible_subformat(WAVEFORMATEX *format, const GUID &subformat) {
  if (format->wFormatTag != WAVE_FORMAT_EXTENSIBLE || format->cbSize < 22) {
    return false;
  }
  auto *extensible = reinterpret_cast<WAVEFORMATEXTENSIBLE *>(format);
  return IsEqualGUID(extensible->SubFormat, subformat) == TRUE;
}

bool is_float_format(WAVEFORMATEX *format) {
  return format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
         is_extensible_subformat(format, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
}

bool is_pcm16_format(WAVEFORMATEX *format) {
  return (format->wFormatTag == WAVE_FORMAT_PCM || is_extensible_subformat(format, KSDATAFORMAT_SUBTYPE_PCM)) &&
         format->wBitsPerSample == 16;
}

void append_i16(std::vector<uint8_t> &output, int16_t value) {
  output.push_back(static_cast<uint8_t>(value & 0xff));
  output.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
}

bool convert_to_mono_s16(BYTE *data, UINT32 frames, WAVEFORMATEX *format, DWORD flags,
                         std::vector<uint8_t> &output, std::string &error) {
  output.clear();
  output.reserve(static_cast<size_t>(frames) * 2);
  const int channels = std::max<int>(1, format->nChannels);
  if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
    output.resize(static_cast<size_t>(frames) * 2, 0);
    return true;
  }

  if (is_float_format(format) && format->wBitsPerSample == 32) {
    const auto *samples = reinterpret_cast<const float *>(data);
    for (UINT32 frame = 0; frame < frames; ++frame) {
      float mixed = 0.0f;
      for (int channel = 0; channel < channels; ++channel) {
        mixed += samples[frame * channels + channel];
      }
      mixed = std::clamp(mixed / static_cast<float>(channels), -1.0f, 1.0f);
      append_i16(output, static_cast<int16_t>(std::lrintf(mixed * 32767.0f)));
    }
    return true;
  }

  if (is_pcm16_format(format)) {
    const auto *samples = reinterpret_cast<const int16_t *>(data);
    for (UINT32 frame = 0; frame < frames; ++frame) {
      int mixed = 0;
      for (int channel = 0; channel < channels; ++channel) {
        mixed += samples[frame * channels + channel];
      }
      append_i16(output, static_cast<int16_t>(mixed / channels));
    }
    return true;
  }

  error = "Unsupported capture format";
  return false;
}

}  // namespace

AudioCapturer::AudioCapturer() = default;

AudioCapturer::~AudioCapturer() {
  stop();
}

bool AudioCapturer::start(RosBridge &bridge, double duration_seconds) {
  if (running_) {
    set_error("Audio capture is already running");
    return false;
  }
  stop_requested_ = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    last_error_.clear();
  }
  thread_ = std::thread([this, &bridge, duration_seconds]() { run(bridge, duration_seconds); });
  return true;
}

void AudioCapturer::stop() {
  stop_requested_ = true;
  if (thread_.joinable()) {
    thread_.join();
  }
}

bool AudioCapturer::is_running() const {
  return running_;
}

std::string AudioCapturer::last_error() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return last_error_;
}

void AudioCapturer::run(RosBridge &bridge, double duration_seconds) {
  running_ = true;
  IMMDeviceEnumerator *enumerator = nullptr;
  IMMDevice *device = nullptr;
  IAudioClient *audio_client = nullptr;
  IAudioCaptureClient *capture_client = nullptr;
  WAVEFORMATEX *format = nullptr;
  bool stream_started = false;
  HRESULT co_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  bool co_initialized = SUCCEEDED(co_result);
  if (co_result == RPC_E_CHANGED_MODE) {
    co_initialized = false;
  } else if (FAILED(co_result)) {
    set_error(hresult_message("CoInitializeEx failed", co_result));
    running_ = false;
    return;
  }

  auto cleanup = [&]() {
    if (stream_started) {
      bridge.end_pcm_stream();
    }
    if (audio_client != nullptr) {
      audio_client->Stop();
    }
    if (format != nullptr) {
      CoTaskMemFree(format);
    }
    safe_release(capture_client);
    safe_release(audio_client);
    safe_release(device);
    safe_release(enumerator);
    if (co_initialized) {
      CoUninitialize();
    }
    running_ = false;
  };

  HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                   __uuidof(IMMDeviceEnumerator), reinterpret_cast<void **>(&enumerator));
  if (FAILED(result)) {
    set_error(hresult_message("MMDeviceEnumerator failed", result));
    cleanup();
    return;
  }
  result = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
  if (FAILED(result)) {
    set_error(hresult_message("GetDefaultAudioEndpoint failed", result));
    cleanup();
    return;
  }
  result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&audio_client));
  if (FAILED(result)) {
    set_error(hresult_message("IAudioClient activation failed", result));
    cleanup();
    return;
  }
  result = audio_client->GetMixFormat(&format);
  if (FAILED(result)) {
    set_error(hresult_message("GetMixFormat failed", result));
    cleanup();
    return;
  }
  if (!is_float_format(format) && !is_pcm16_format(format)) {
    set_error("Default capture format is not float32 or PCM16");
    cleanup();
    return;
  }
  result = audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 1000000, 0, format, nullptr);
  if (FAILED(result)) {
    set_error(hresult_message("IAudioClient Initialize failed", result));
    cleanup();
    return;
  }
  result = audio_client->GetService(__uuidof(IAudioCaptureClient), reinterpret_cast<void **>(&capture_client));
  if (FAILED(result)) {
    set_error(hresult_message("IAudioCaptureClient service failed", result));
    cleanup();
    return;
  }

  if (!bridge.begin_pcm_stream(static_cast<int>(format->nSamplesPerSec), 1, 2)) {
    cleanup();
    return;
  }
  stream_started = true;
  result = audio_client->Start();
  if (FAILED(result)) {
    set_error(hresult_message("IAudioClient Start failed", result));
    cleanup();
    return;
  }

  auto started_at = std::chrono::steady_clock::now();
  std::vector<uint8_t> pcm;
  while (!stop_requested_) {
    if (duration_seconds > 0.0) {
      auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started_at).count();
      if (elapsed >= duration_seconds) {
        break;
      }
    }
    UINT32 packet_frames = 0;
    result = capture_client->GetNextPacketSize(&packet_frames);
    if (FAILED(result)) {
      set_error(hresult_message("GetNextPacketSize failed", result));
      break;
    }
    if (packet_frames == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    while (packet_frames != 0) {
      BYTE *data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      result = capture_client->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
      if (FAILED(result)) {
        set_error(hresult_message("GetBuffer failed", result));
        break;
      }
      std::string error;
      bool converted = convert_to_mono_s16(data, frames, format, flags, pcm, error);
      capture_client->ReleaseBuffer(frames);
      if (!converted) {
        set_error(error);
        stop_requested_ = true;
        break;
      }
      if (!pcm.empty() && !bridge.publish_pcm_chunk(pcm.data(), pcm.size())) {
        stop_requested_ = true;
        break;
      }
      result = capture_client->GetNextPacketSize(&packet_frames);
      if (FAILED(result)) {
        set_error(hresult_message("GetNextPacketSize failed", result));
        stop_requested_ = true;
        break;
      }
    }
  }
  cleanup();
}

void AudioCapturer::set_error(const std::string &message) {
  std::lock_guard<std::mutex> lock(mutex_);
  last_error_ = message;
}