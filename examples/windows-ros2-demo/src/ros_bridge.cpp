#include "ros_bridge.h"

#include "wav_io.h"

#include <Windows.h>

#include <chrono>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <stdexcept>

#include <rmw/error_handling.h>

namespace {

constexpr const char *kRmwImplementation = "rmw_fastrtps_cpp";

bool is_valid_node_name(const std::string &value) {
  if (value.empty()) {
    return false;
  }
  unsigned char first = static_cast<unsigned char>(value.front());
  if (!std::isalpha(first) && value.front() != '_') {
    return false;
  }
  for (char character : value) {
    unsigned char current = static_cast<unsigned char>(character);
    if (!std::isalnum(current) && character != '_') {
      return false;
    }
  }
  return true;
}

std::string json_escape(const std::string &value) {
  std::ostringstream escaped;
  for (char character : value) {
    switch (character) {
      case '\\': escaped << "\\\\"; break;
      case '"': escaped << "\\\""; break;
      case '\n': escaped << "\\n"; break;
      case '\r': escaped << "\\r"; break;
      case '\t': escaped << "\\t"; break;
      default: escaped << character; break;
    }
  }
  return escaped.str();
}

void set_process_env(const std::string &name, const std::string &value) {
  if (value.empty()) {
    _putenv_s(name.c_str(), "");
    SetEnvironmentVariableA(name.c_str(), nullptr);
  } else {
    _putenv_s(name.c_str(), value.c_str());
    SetEnvironmentVariableA(name.c_str(), value.c_str());
  }
}

std::string with_rmw_error(const char *message) {
  std::string result = message;
  const rcutils_error_string_t rmw_error = rmw_get_error_string();
  if (std::string(rmw_error.str) != "error not set") {
    result += "; rmw: ";
    result += rmw_error.str;
  }
  return result;
}

int parse_positive_int(const std::string &value, int fallback) {
  try {
    int parsed = std::stoi(value);
    return parsed > 0 ? parsed : fallback;
  } catch (...) {
    return fallback;
  }
}

}  // namespace

RosBridge::RosBridge() = default;

RosBridge::~RosBridge() {
  stop();
}

bool RosBridge::start(RuntimeConfig config) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (running_) {
    last_error_.clear();
    return true;
  }
  if (!is_valid_node_name(config.node_name)) {
    last_error_ = "Invalid node name";
    state_ = "failed";
    return false;
  }

  config_ = std::move(config);
  if (config_.publish_rate_hz <= 0.0) {
    config_.publish_rate_hz = 1.0;
  }
  state_ = "starting";
  tx_state_ = "idle";
  rx_state_ = "idle";
  last_error_.clear();
  last_android_status_.clear();
  android_status_count_ = 0;
  command_count_ = 0;
  tx_chunk_count_ = 0;
  tx_bytes_ = 0;
  rx_chunk_count_ = 0;
  rx_bytes_ = 0;

  try {
    set_process_env("ROS_DOMAIN_ID", std::to_string(config_.domain_id));
    set_process_env("RMW_IMPLEMENTATION", kRmwImplementation);
    set_process_env("ROS_DISCOVERY_SERVER", config_.discovery_server);

    context_ = std::make_shared<rclcpp::Context>();
    rclcpp::InitOptions init_options;
    context_->init(0, nullptr, init_options);

    rclcpp::NodeOptions node_options;
    node_options.context(context_);
    node_ = std::make_shared<rclcpp::Node>(config_.node_name, node_options);
    node_->declare_parameter<double>("publish_rate_hz", config_.publish_rate_hz);
    node_->declare_parameter<std::string>("qos_mode", config_.qos_mode);

    auto qos = make_qos(config_.qos_mode);
    auto audio_qos = rclcpp::QoS(32).reliable();
    command_publisher_ = node_->create_publisher<std_msgs::msg::String>("/android/command", qos);
    audio_control_publisher_ = node_->create_publisher<std_msgs::msg::String>("/android/audio_control", audio_qos);
    audio_chunk_publisher_ = node_->create_publisher<std_msgs::msg::UInt8MultiArray>("/android/audio_chunk", audio_qos);
    status_subscription_ = node_->create_subscription<std_msgs::msg::String>(
        "/android/status", qos, [this](std_msgs::msg::String::SharedPtr message) {
          handle_android_status(message->data);
        });
    rx_audio_control_subscription_ = node_->create_subscription<std_msgs::msg::String>(
        "/wsl/audio_control", audio_qos, [this](std_msgs::msg::String::SharedPtr message) {
          handle_rx_audio_control(message->data);
        });
    rx_audio_chunk_subscription_ = node_->create_subscription<std_msgs::msg::UInt8MultiArray>(
        "/wsl/audio_chunk", audio_qos, [this](std_msgs::msg::UInt8MultiArray::SharedPtr message) {
          handle_rx_audio_chunk(*message);
        });

    rclcpp::ExecutorOptions executor_options;
    executor_options.context = context_;
    executor_ = std::make_shared<rclcpp::executors::SingleThreadedExecutor>(executor_options);
    executor_->add_node(node_);
    running_ = true;
    state_ = "running";
    executor_thread_ = std::thread([this]() {
      try {
        executor_->spin();
      } catch (const std::exception &error) {
        set_error(error.what());
      }
    });
    return true;
  } catch (const std::exception &error) {
    last_error_ = with_rmw_error(error.what());
    state_ = "failed";
    cleanup_locked();
    return false;
  }
}

void RosBridge::stop() {
  std::shared_ptr<rclcpp::executors::SingleThreadedExecutor> executor;
  std::shared_ptr<rclcpp::Context> context;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ && state_ != "failed") {
      state_ = "stopped";
      return;
    }
    running_ = false;
    state_ = "stopping";
    cancel_tx_ = true;
    executor = executor_;
    context = context_;
  }
  if (executor) {
    executor->cancel();
  }
  if (context && context->is_valid()) {
    context->shutdown("Windows ROS 2 demo stopped");
  }
  if (executor_thread_.joinable()) {
    executor_thread_.join();
  }
  if (tx_thread_.joinable()) {
    tx_thread_.join();
  }
  tx_thread_active_ = false;
  std::lock_guard<std::mutex> lock(mutex_);
  cleanup_locked();
  state_ = "stopped";
}

bool RosBridge::is_running() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return running_;
}

bool RosBridge::send_command(const std::string &command) {
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !command_publisher_) {
      last_error_ = "Session is not running";
      return false;
    }
    publisher = command_publisher_;
  }
  std_msgs::msg::String message;
  message.data = command;
  try {
    publisher->publish(message);
    std::lock_guard<std::mutex> lock(mutex_);
    ++command_count_;
    return true;
  } catch (const std::exception &error) {
    set_error(with_rmw_error(error.what()));
    return false;
  }
}

bool RosBridge::send_wav_file(const std::string &path, double send_speed) {
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr control_publisher;
  rclcpp::Publisher<std_msgs::msg::UInt8MultiArray>::SharedPtr chunk_publisher;
  WavInfo info;
  std::string error;
  if (!read_wav_info(path, info, error)) {
    set_error(error);
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !audio_control_publisher_ || !audio_chunk_publisher_) {
      last_error_ = "Session is not running";
      return false;
    }
    if (tx_thread_.joinable() && !tx_thread_active_) {
      tx_thread_.join();
    }
    if (tx_thread_active_) {
      last_error_ = "Audio TX is already running";
      return false;
    }
    control_publisher = audio_control_publisher_;
    chunk_publisher = audio_chunk_publisher_;
    tx_state_ = "streaming";
    tx_chunk_count_ = 0;
    tx_bytes_ = 0;
    cancel_tx_ = false;
    tx_thread_active_ = true;
  }

  double speed = send_speed > 0.0 ? send_speed : 1.0;
  tx_thread_ = std::thread([this, path, info, speed, control_publisher, chunk_publisher]() {
    try {
      std_msgs::msg::String control;
      control.data = "begin_stream:" + std::to_string(info.sample_rate) + ":" +
                     std::to_string(info.channels) + ":" + std::to_string(info.sample_width);
      control_publisher->publish(control);
      std::this_thread::sleep_for(std::chrono::milliseconds(200));

      std::ifstream stream(path, std::ios::binary);
      stream.seekg(info.data_offset, std::ios::beg);
      const size_t chunk_size = 4096;
      std::vector<uint8_t> buffer(chunk_size);
      const double bytes_per_second = static_cast<double>(info.sample_rate) * info.channels * info.sample_width;
      while (!cancel_tx_ && stream) {
        stream.read(reinterpret_cast<char *>(buffer.data()), static_cast<std::streamsize>(buffer.size()));
        std::streamsize read = stream.gcount();
        if (read <= 0) {
          break;
        }
        std_msgs::msg::UInt8MultiArray message;
        message.data.assign(buffer.begin(), buffer.begin() + read);
        chunk_publisher->publish(message);
        {
          std::lock_guard<std::mutex> lock(mutex_);
          ++tx_chunk_count_;
          tx_bytes_ += static_cast<uint64_t>(read);
        }
        double seconds = (static_cast<double>(read) / bytes_per_second) / speed;
        if (seconds > 0.0) {
          std::this_thread::sleep_for(std::chrono::duration<double>(seconds));
        }
      }

      control.data = "end_stream";
      control_publisher->publish(control);
      std::lock_guard<std::mutex> lock(mutex_);
      tx_state_ = cancel_tx_ ? "cancelled" : "done";
      tx_thread_active_ = false;
    } catch (const std::exception &error) {
      set_error(with_rmw_error(error.what()));
      std::lock_guard<std::mutex> lock(mutex_);
      tx_state_ = "failed";
      tx_thread_active_ = false;
    }
  });
  return true;
}

void RosBridge::cancel_audio_tx() {
  cancel_tx_ = true;
  if (tx_thread_.joinable()) {
    tx_thread_.join();
  }
  tx_thread_active_ = false;
}

bool RosBridge::begin_pcm_stream(int sample_rate, int channels, int sample_width) {
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !audio_control_publisher_) {
      last_error_ = "Session is not running";
      return false;
    }
    publisher = audio_control_publisher_;
    tx_state_ = "streaming";
    tx_chunk_count_ = 0;
    tx_bytes_ = 0;
  }
  std_msgs::msg::String message;
  message.data = "begin_stream:" + std::to_string(sample_rate) + ":" +
                 std::to_string(channels) + ":" + std::to_string(sample_width);
  try {
    publisher->publish(message);
    return true;
  } catch (const std::exception &error) {
    set_error(with_rmw_error(error.what()));
    return false;
  }
}

bool RosBridge::publish_pcm_chunk(const uint8_t *data, size_t length) {
  rclcpp::Publisher<std_msgs::msg::UInt8MultiArray>::SharedPtr publisher;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !audio_chunk_publisher_) {
      last_error_ = "Session is not running";
      return false;
    }
    publisher = audio_chunk_publisher_;
  }
  std_msgs::msg::UInt8MultiArray message;
  if (data != nullptr && length > 0) {
    message.data.assign(data, data + length);
  }
  try {
    publisher->publish(message);
    std::lock_guard<std::mutex> lock(mutex_);
    ++tx_chunk_count_;
    tx_bytes_ += length;
    return true;
  } catch (const std::exception &error) {
    set_error(with_rmw_error(error.what()));
    return false;
  }
}

bool RosBridge::end_pcm_stream() {
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !audio_control_publisher_) {
      last_error_ = "Session is not running";
      return false;
    }
    publisher = audio_control_publisher_;
  }
  std_msgs::msg::String message;
  message.data = "end_stream";
  try {
    publisher->publish(message);
    std::lock_guard<std::mutex> lock(mutex_);
    tx_state_ = "done";
    return true;
  } catch (const std::exception &error) {
    set_error(with_rmw_error(error.what()));
    return false;
  }
}

std::string RosBridge::snapshot_json() const {
  std::lock_guard<std::mutex> lock(mutex_);
  std::ostringstream json;
  json << "{\n";
  json << "  \"runtimeState\": \"" << json_escape(state_) << "\",\n";
  json << "  \"nodeName\": \"" << json_escape(config_.node_name) << "\",\n";
  json << "  \"domainId\": " << config_.domain_id << ",\n";
  json << "  \"rmwImplementation\": \"" << kRmwImplementation << "\",\n";
  json << "  \"discoveryServer\": \"" << json_escape(config_.discovery_server) << "\",\n";
  json << "  \"qosMode\": \"" << json_escape(config_.qos_mode) << "\",\n";
  json << "  \"androidStatusCount\": " << android_status_count_ << ",\n";
  json << "  \"sentCommandCount\": " << command_count_ << ",\n";
  json << "  \"txState\": \"" << json_escape(tx_state_) << "\",\n";
  json << "  \"txChunkCount\": " << tx_chunk_count_ << ",\n";
  json << "  \"txBytes\": " << tx_bytes_ << ",\n";
  json << "  \"rxState\": \"" << json_escape(rx_state_) << "\",\n";
  json << "  \"rxChunkCount\": " << rx_chunk_count_ << ",\n";
  json << "  \"rxBytes\": " << rx_bytes_ << ",\n";
  json << "  \"latestReceivedPath\": \"" << json_escape(latest_received_path_) << "\",\n";
  json << "  \"lastAndroidStatus\": \"" << json_escape(last_android_status_) << "\",\n";
  json << "  \"lastError\": \"" << json_escape(last_error_) << "\"\n";
  json << "}";
  return json.str();
}

std::string RosBridge::latest_received_path() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return latest_received_path_;
}

std::string RosBridge::last_error() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return last_error_;
}

rclcpp::QoS RosBridge::make_qos(const std::string &qos_mode) const {
  rclcpp::QoS qos(10);
  if (qos_mode == "best_effort") {
    qos.best_effort();
  } else {
    qos.reliable();
  }
  return qos;
}

void RosBridge::handle_android_status(const std::string &status) {
  std::lock_guard<std::mutex> lock(mutex_);
  last_android_status_ = status;
  ++android_status_count_;
}

void RosBridge::handle_rx_audio_control(const std::string &command) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (command.rfind("begin_stream:", 0) == 0) {
    int rate = 16000;
    int channels = 1;
    int sample_width = 2;
    std::istringstream values(command.substr(13));
    std::string token;
    if (std::getline(values, token, ':')) {
      rate = parse_positive_int(token, rate);
    }
    if (std::getline(values, token, ':')) {
      channels = parse_positive_int(token, channels);
    }
    if (std::getline(values, token, ':')) {
      sample_width = parse_positive_int(token, sample_width);
    }
    close_rx_stream_locked();
    rx_sample_rate_ = rate;
    rx_channels_ = channels;
    rx_sample_width_ = sample_width;
    rx_bytes_ = 0;
    rx_chunk_count_ = 0;
    latest_received_path_ = make_received_path();
    std::filesystem::create_directories(std::filesystem::path(latest_received_path_).parent_path());
    rx_stream_.open(latest_received_path_, std::ios::binary | std::ios::trunc);
    if (!rx_stream_) {
      rx_state_ = "failed";
      last_error_ = "Failed to open received WAV file";
      return;
    }
    write_wav_header(rx_stream_, rx_sample_rate_, static_cast<uint16_t>(rx_channels_),
                     static_cast<uint16_t>(rx_sample_width_), 0);
    rx_state_ = "streaming";
  } else if (command == "end_stream" || command == "end") {
    close_rx_stream_locked();
    rx_state_ = latest_received_path_.empty() ? "idle" : "ready";
  }
}

void RosBridge::handle_rx_audio_chunk(const std_msgs::msg::UInt8MultiArray &message) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!rx_stream_.is_open() || message.data.empty()) {
    return;
  }
  rx_stream_.write(reinterpret_cast<const char *>(message.data.data()),
                   static_cast<std::streamsize>(message.data.size()));
  if (!rx_stream_) {
    rx_state_ = "failed";
    last_error_ = "Failed while writing received audio";
    return;
  }
  ++rx_chunk_count_;
  rx_bytes_ += message.data.size();
}

void RosBridge::close_rx_stream_locked() {
  if (rx_stream_.is_open()) {
    rx_stream_.flush();
    write_wav_header(rx_stream_, rx_sample_rate_, static_cast<uint16_t>(rx_channels_),
                     static_cast<uint16_t>(rx_sample_width_), static_cast<uint32_t>(rx_bytes_));
    rx_stream_.flush();
    rx_stream_.close();
  }
}

std::string RosBridge::make_received_path() const {
  char local_app_data[MAX_PATH] = {};
  DWORD length = GetEnvironmentVariableA("LOCALAPPDATA", local_app_data, MAX_PATH);
  std::filesystem::path base = length > 0 ? std::filesystem::path(local_app_data)
                                          : std::filesystem::temp_directory_path();
  SYSTEMTIME time;
  GetLocalTime(&time);
  std::ostringstream name;
  name << "received_" << std::setfill('0') << std::setw(4) << time.wYear
       << std::setw(2) << time.wMonth << std::setw(2) << time.wDay << "_"
       << std::setw(2) << time.wHour << std::setw(2) << time.wMinute
       << std::setw(2) << time.wSecond << ".wav";
  return (base / "Ros2Builder" / "received" / name.str()).string();
}

void RosBridge::set_error(const std::string &message) {
  std::lock_guard<std::mutex> lock(mutex_);
  last_error_ = message;
}

void RosBridge::cleanup_locked() {
  close_rx_stream_locked();
  rx_audio_chunk_subscription_.reset();
  rx_audio_control_subscription_.reset();
  status_subscription_.reset();
  audio_chunk_publisher_.reset();
  audio_control_publisher_.reset();
  command_publisher_.reset();
  if (executor_ && node_) {
    try {
      executor_->remove_node(node_);
    } catch (...) {
    }
  }
  executor_.reset();
  node_.reset();
  context_.reset();
  running_ = false;
}