#pragma once

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

class RosBridge;

class AudioCapturer {
 public:
  AudioCapturer();
  ~AudioCapturer();

  bool start(RosBridge &bridge, double duration_seconds);
  void stop();
  bool is_running() const;
  std::string last_error() const;

 private:
  void run(RosBridge &bridge, double duration_seconds);
  void set_error(const std::string &message);

  mutable std::mutex mutex_;
  std::thread thread_;
  std::atomic_bool stop_requested_{false};
  std::atomic_bool running_{false};
  std::string last_error_;
};