#pragma once

#include <atomic>
#include <cstdint>
#include <deque>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>
#include <std_msgs/msg/u_int8_multi_array.hpp>

struct RuntimeConfig {
  int domain_id = 0;
  std::string node_name = "windows_ros2_demo";
  double publish_rate_hz = 1.0;
  std::string qos_mode = "reliable";
  std::string discovery_server;
};

class RosBridge {
 public:
  RosBridge();
  ~RosBridge();

  bool start(RuntimeConfig config);
  void stop();
  bool is_running() const;

  bool send_command(const std::string &command);
  bool send_wav_file(const std::string &path, double send_speed);
  void cancel_audio_tx();
  bool begin_pcm_stream(int sample_rate, int channels, int sample_width);
  bool publish_pcm_chunk(const uint8_t *data, size_t length);
  bool end_pcm_stream();

  std::string snapshot_json() const;
  std::string latest_received_path() const;
  std::string last_error() const;

 private:
  rclcpp::QoS make_qos(const std::string &qos_mode) const;
  void handle_android_status(const std::string &status);
  void handle_rx_audio_control(const std::string &command);
  void handle_rx_audio_chunk(const std_msgs::msg::UInt8MultiArray &message);
  void close_rx_stream_locked();
  std::string make_received_path() const;
  void set_error(const std::string &message);
  void cleanup_locked();

  mutable std::mutex mutex_;
  RuntimeConfig config_;
  std::string state_ = "stopped";
  std::string tx_state_ = "idle";
  std::string rx_state_ = "idle";
  std::string latest_received_path_;
  std::string last_android_status_;
  std::string last_error_;
  bool running_ = false;
  int rx_sample_rate_ = 16000;
  int rx_channels_ = 1;
  int rx_sample_width_ = 2;
  uint64_t android_status_count_ = 0;
  uint64_t command_count_ = 0;
  uint64_t tx_chunk_count_ = 0;
  uint64_t tx_bytes_ = 0;
  uint64_t rx_chunk_count_ = 0;
  uint64_t rx_bytes_ = 0;

  std::shared_ptr<rclcpp::Context> context_;
  std::shared_ptr<rclcpp::Node> node_;
  std::shared_ptr<rclcpp::executors::SingleThreadedExecutor> executor_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr command_publisher_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr audio_control_publisher_;
  rclcpp::Publisher<std_msgs::msg::UInt8MultiArray>::SharedPtr audio_chunk_publisher_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr status_subscription_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr rx_audio_control_subscription_;
  rclcpp::Subscription<std_msgs::msg::UInt8MultiArray>::SharedPtr rx_audio_chunk_subscription_;
  std::thread executor_thread_;
  std::thread tx_thread_;
  std::atomic_bool cancel_tx_{false};
  std::atomic_bool tx_thread_active_{false};
  std::ofstream rx_stream_;
};