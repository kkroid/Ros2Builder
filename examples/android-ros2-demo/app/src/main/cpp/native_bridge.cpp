#include <jni.h>
#include <android/log.h>

#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <deque>
#include <exception>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <rclcpp/rclcpp.hpp>
#include <rmw/error_handling.h>
#include <std_msgs/msg/string.hpp>
#include <std_msgs/msg/u_int8_multi_array.hpp>

namespace {

constexpr const char *kLogTag = "Ros2AndroidDemo";
constexpr const char *kRmwImplementation = "rmw_fastrtps_dynamic_cpp";

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

std::string with_rmw_error(const char *message) {
  std::string result = message;
  const rcutils_error_string_t rmw_error = rmw_get_error_string();
  if (std::string(rmw_error.str) != "error not set") {
    result += "; rmw: ";
    result += rmw_error.str;
  }
  return result;
}

class RosDemoRuntime {
 public:
  bool start(
      int domain_id,
      std::string node_name,
      double publish_rate_hz,
      std::string qos_mode,
      std::string discovery_server,
      std::string audio_file_path) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (running_) {
      last_error_.clear();
      return true;
    }

    domain_id_ = domain_id;
    node_name_ = std::move(node_name);
    publish_rate_hz_ = publish_rate_hz > 0.0 ? publish_rate_hz : 1.0;
    qos_mode_ = std::move(qos_mode);
    discovery_server_ = std::move(discovery_server);
    audio_file_path_ = std::move(audio_file_path);
    published_count_ = 0;
    received_count_ = 0;
    audio_chunk_count_ = 0;
    audio_transfer_count_ = 0;
    audio_file_bytes_ = file_size(audio_file_path_);
    audio_receiving_ = false;
    audio_state_ = "idle";
    last_command_.clear();
    last_error_.clear();
    state_ = "starting";

    try {
      if (!is_valid_node_name(node_name_)) {
        throw std::invalid_argument(
            "Invalid node name. Use letters, numbers and '_' only; do not include '/'.");
      }

      setenv("ROS_DOMAIN_ID", std::to_string(domain_id_).c_str(), 1);
      setenv("RMW_IMPLEMENTATION", kRmwImplementation, 1);
      if (discovery_server_.empty()) {
        unsetenv("ROS_DISCOVERY_SERVER");
      } else {
        setenv("ROS_DISCOVERY_SERVER", discovery_server_.c_str(), 1);
      }

      context_ = std::make_shared<rclcpp::Context>();
      rclcpp::InitOptions init_options;
      context_->init(0, nullptr, init_options);

      rclcpp::NodeOptions node_options;
      node_options.context(context_);
      node_ = std::make_shared<rclcpp::Node>(node_name_, node_options);
      node_->declare_parameter<double>("publish_rate_hz", publish_rate_hz_);
      node_->declare_parameter<std::string>("qos_mode", qos_mode_);

      auto qos = make_qos(qos_mode_);
      auto audio_qos = rclcpp::QoS(10).reliable();
      publisher_ = node_->create_publisher<std_msgs::msg::String>("/android/status", qos);
      subscription_ = node_->create_subscription<std_msgs::msg::String>(
          "/android/command",
          qos,
          [this](std_msgs::msg::String::SharedPtr message) {
            handle_command(message->data);
          });
      audio_control_subscription_ = node_->create_subscription<std_msgs::msg::String>(
          "/android/audio_control",
          audio_qos,
          [this](std_msgs::msg::String::SharedPtr message) {
            handle_audio_control(message->data);
          });
      audio_chunk_subscription_ = node_->create_subscription<std_msgs::msg::UInt8MultiArray>(
          "/android/audio_chunk",
          audio_qos,
          [this](std_msgs::msg::UInt8MultiArray::SharedPtr message) {
            handle_audio_chunk(*message);
          });
      tx_audio_control_publisher_ = node_->create_publisher<std_msgs::msg::String>(
          "/wsl/audio_control", audio_qos);
      tx_audio_chunk_publisher_ = node_->create_publisher<std_msgs::msg::UInt8MultiArray>(
          "/wsl/audio_chunk", audio_qos);

      rebuild_timer_locked();

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
      __android_log_print(ANDROID_LOG_ERROR, kLogTag, "%s", last_error_.c_str());
      cleanup_locked();
      return false;
    }
  }

  void stop() {
    std::shared_ptr<rclcpp::executors::SingleThreadedExecutor> executor;
    std::shared_ptr<rclcpp::Context> context;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!running_ && state_ != "failed") {
        state_ = "stopped";
        return;
      }
      state_ = "stopping";
      running_ = false;
      executor = executor_;
      context = context_;
    }

    if (executor) {
      executor->cancel();
    }
    if (context && context->is_valid()) {
      context->shutdown("Android demo stopped");
    }
    if (executor_thread_.joinable()) {
      executor_thread_.join();
    }

    std::lock_guard<std::mutex> lock(mutex_);
    cleanup_locked();
    state_ = "stopped";
  }

  bool send_local_command(const std::string &command) {
    handle_command(command);
    return true;
  }

  bool publish_tx_audio_control(const std::string &command) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !tx_audio_control_publisher_) {
      last_error_ = "Cannot publish: session not running";
      return false;
    }
    std_msgs::msg::String message;
    message.data = command;
    try {
      tx_audio_control_publisher_->publish(message);
      return true;
    } catch (const std::exception &error) {
      last_error_ = with_rmw_error(error.what());
      __android_log_print(ANDROID_LOG_ERROR, kLogTag, "publish tx control failed: %s",
                          last_error_.c_str());
      return false;
    }
  }

  bool publish_tx_audio_chunk(const uint8_t *data, size_t length) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || !tx_audio_chunk_publisher_) {
      last_error_ = "Cannot publish: session not running";
      return false;
    }
    std_msgs::msg::UInt8MultiArray message;
    if (data != nullptr && length > 0) {
      message.data.assign(data, data + length);
    }
    try {
      tx_audio_chunk_publisher_->publish(message);
      return true;
    } catch (const std::exception &error) {
      last_error_ = with_rmw_error(error.what());
      __android_log_print(ANDROID_LOG_ERROR, kLogTag, "publish tx chunk failed: %s",
                          last_error_.c_str());
      return false;
    }
  }

  std::string snapshot() {
    std::lock_guard<std::mutex> lock(mutex_);
    std::ostringstream json;
    json << "{\n";
    json << "  \"runtimeState\": \"" << json_escape(state_) << "\",\n";
    json << "  \"nodeName\": \"" << json_escape(node_name_) << "\",\n";
    json << "  \"domainId\": " << domain_id_ << ",\n";
    json << "  \"rmwImplementation\": \"" << kRmwImplementation << "\",\n";
    json << "  \"discoveryServer\": \"" << json_escape(discovery_server_) << "\",\n";
    json << "  \"publishRateHz\": " << publish_rate_hz_ << ",\n";
    json << "  \"qosMode\": \"" << json_escape(qos_mode_) << "\",\n";
    json << "  \"publishedCount\": " << published_count_ << ",\n";
    json << "  \"receivedCommandCount\": " << received_count_ << ",\n";
    json << "  \"audioState\": \"" << json_escape(audio_state_) << "\",\n";
    json << "  \"audioFileBytes\": " << audio_file_bytes_ << ",\n";
    json << "  \"audioChunkCount\": " << audio_chunk_count_ << ",\n";
    json << "  \"audioTransferCount\": " << audio_transfer_count_ << ",\n";
    json << "  \"lastCommand\": \"" << json_escape(last_command_) << "\",\n";
    json << "  \"lastError\": \"" << json_escape(last_error_) << "\"\n";
    json << "}";
    return json.str();
  }

  uint64_t audio_file_bytes() {
    std::lock_guard<std::mutex> lock(mutex_);
    audio_file_bytes_ = file_size(audio_file_path_);
    return audio_file_bytes_;
  }

  std::vector<uint8_t> drain_audio_pcm() {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<uint8_t> result;
    while (!audio_playback_queue_.empty()) {
      auto &chunk = audio_playback_queue_.front();
      result.insert(result.end(), chunk.begin(), chunk.end());
      audio_playback_queued_bytes_ -= chunk.size();
      audio_playback_queue_.pop_front();
      if (result.size() >= 8192) {
        break;
      }
    }
    return result;
  }

 private:
  rclcpp::QoS make_qos(const std::string &qos_mode) {
    rclcpp::QoS qos(10);
    if (qos_mode == "reliable") {
      qos.reliable();
    } else {
      qos.best_effort();
    }
    return qos;
  }

  void publish_status() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!publisher_ || !running_) {
      return;
    }
    std_msgs::msg::String message;
    std::ostringstream payload;
    payload << "{\"seq\":" << (published_count_ + 1)
            << ",\"device\":\"android\""
            << ",\"state\":\"" << json_escape(state_) << "\""
            << ",\"lastCommand\":\"" << json_escape(last_command_) << "\"}";
    message.data = payload.str();
    publisher_->publish(message);
    ++published_count_;
  }

  void handle_command(const std::string &command) {
    std::lock_guard<std::mutex> lock(mutex_);
    last_command_ = command;
    ++received_count_;
    if (command.rfind("set_rate:", 0) == 0) {
      try {
        double new_rate = std::stod(command.substr(9));
        if (new_rate > 0.0) {
          publish_rate_hz_ = new_rate;
          if (node_) {
            node_->set_parameter(rclcpp::Parameter("publish_rate_hz", publish_rate_hz_));
            rebuild_timer_locked();
          }
        }
      } catch (const std::exception &error) {
        last_error_ = error.what();
      }
    } else if (command == "reset_metrics") {
      published_count_ = 0;
      received_count_ = 0;
    }
  }

  void handle_audio_control(const std::string &command) {
    if (command.rfind("begin_stream:", 0) == 0) {
      begin_audio_stream(command);
    } else if (command == "begin") {
      begin_audio_transfer(false);
    } else if (command == "end" || command == "end_stream") {
      end_audio_transfer();
    }
  }

  void begin_audio_stream(const std::string &command) {
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

    if (sample_width != 2 || channels != 1) {
      std::lock_guard<std::mutex> lock(mutex_);
      last_error_ = "Only mono 16-bit PCM streaming is supported";
      audio_state_ = "failed";
      return;
    }

    audio_sample_rate_ = rate;
    audio_channels_ = channels;
    audio_sample_width_ = sample_width;
    begin_audio_transfer(true);
  }

  int parse_positive_int(const std::string &value, int fallback) {
    try {
      int parsed = std::stoi(value);
      return parsed > 0 ? parsed : fallback;
    } catch (...) {
      return fallback;
    }
  }

  void begin_audio_transfer(bool streaming_pcm) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (audio_stream_.is_open()) {
      audio_stream_.close();
    }
    audio_stream_.open(audio_file_path_, std::ios::binary | std::ios::trunc);
    if (!audio_stream_) {
      audio_receiving_ = false;
      audio_state_ = "failed";
      last_error_ = "Failed to open audio file for writing";
      __android_log_print(ANDROID_LOG_ERROR, kLogTag, "%s: %s", last_error_.c_str(), audio_file_path_.c_str());
      return;
    }
    audio_streaming_pcm_ = streaming_pcm;
    audio_pcm_bytes_ = 0;
    audio_playback_queue_.clear();
    audio_playback_queued_bytes_ = 0;
    if (audio_streaming_pcm_) {
      write_wav_header_locked(0);
    }
    audio_receiving_ = true;
    audio_state_ = streaming_pcm ? "streaming" : "receiving";
    audio_file_bytes_ = streaming_pcm ? 44 : 0;
    audio_chunk_count_ = 0;
    ++audio_transfer_count_;
  }

  void handle_audio_chunk(const std_msgs::msg::UInt8MultiArray &message) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!audio_receiving_ || !audio_stream_.is_open()) {
      return;
    }
    if (!message.data.empty()) {
      audio_stream_.write(
          reinterpret_cast<const char *>(message.data.data()),
          static_cast<std::streamsize>(message.data.size()));
      if (!audio_stream_) {
        audio_receiving_ = false;
        audio_state_ = "failed";
        last_error_ = "Failed while writing audio file";
        __android_log_print(ANDROID_LOG_ERROR, kLogTag, "%s", last_error_.c_str());
        return;
      }
      if (audio_streaming_pcm_) {
        audio_pcm_bytes_ += message.data.size();
        enqueue_playback_locked(message.data);
      }
      audio_file_bytes_ += message.data.size();
    }
    ++audio_chunk_count_;
  }

  void end_audio_transfer() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (audio_stream_.is_open()) {
      audio_stream_.flush();
      if (audio_streaming_pcm_) {
        write_wav_header_locked(audio_pcm_bytes_);
        audio_stream_.flush();
      }
      audio_stream_.close();
    }
    audio_receiving_ = false;
    audio_file_bytes_ = file_size(audio_file_path_);
    audio_state_ = audio_file_bytes_ > 0 ? "ready" : "empty";
  }

  void enqueue_playback_locked(const std::vector<uint8_t> &chunk) {
    audio_playback_queue_.push_back(chunk);
    audio_playback_queued_bytes_ += chunk.size();
    while (audio_playback_queued_bytes_ > 262144 && !audio_playback_queue_.empty()) {
      audio_playback_queued_bytes_ -= audio_playback_queue_.front().size();
      audio_playback_queue_.pop_front();
    }
  }

  void write_wav_header_locked(uint32_t pcm_bytes) {
    if (!audio_stream_) {
      return;
    }
    audio_stream_.seekp(0, std::ios::beg);
    write_ascii_locked("RIFF");
    write_u32_locked(36 + pcm_bytes);
    write_ascii_locked("WAVE");
    write_ascii_locked("fmt ");
    write_u32_locked(16);
    write_u16_locked(1);
    write_u16_locked(static_cast<uint16_t>(audio_channels_));
    write_u32_locked(static_cast<uint32_t>(audio_sample_rate_));
    write_u32_locked(static_cast<uint32_t>(audio_sample_rate_ * audio_channels_ * audio_sample_width_));
    write_u16_locked(static_cast<uint16_t>(audio_channels_ * audio_sample_width_));
    write_u16_locked(static_cast<uint16_t>(audio_sample_width_ * 8));
    write_ascii_locked("data");
    write_u32_locked(pcm_bytes);
    audio_stream_.seekp(0, std::ios::end);
  }

  void write_ascii_locked(const char *value) {
    audio_stream_.write(value, 4);
  }

  void write_u16_locked(uint16_t value) {
    char bytes[2] = {
        static_cast<char>(value & 0xff),
        static_cast<char>((value >> 8) & 0xff)};
    audio_stream_.write(bytes, sizeof(bytes));
  }

  void write_u32_locked(uint32_t value) {
    char bytes[4] = {
        static_cast<char>(value & 0xff),
        static_cast<char>((value >> 8) & 0xff),
        static_cast<char>((value >> 16) & 0xff),
        static_cast<char>((value >> 24) & 0xff)};
    audio_stream_.write(bytes, sizeof(bytes));
  }

  void set_error(const std::string &error) {
    std::lock_guard<std::mutex> lock(mutex_);
    last_error_ = error;
    __android_log_print(ANDROID_LOG_ERROR, kLogTag, "%s", error.c_str());
  }

  void rebuild_timer_locked() {
    if (!node_) {
      return;
    }
    timer_.reset();
    auto period = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_rate_hz_));
    timer_ = node_->create_wall_timer(period, [this]() { publish_status(); });
  }

  void cleanup_locked() {
    if (audio_stream_.is_open()) {
      audio_stream_.close();
    }
    audio_receiving_ = false;
    audio_playback_queue_.clear();
    audio_playback_queued_bytes_ = 0;
    timer_.reset();
    audio_chunk_subscription_.reset();
    audio_control_subscription_.reset();
    subscription_.reset();
    publisher_.reset();
    tx_audio_chunk_publisher_.reset();
    tx_audio_control_publisher_.reset();
    if (executor_ && node_) {
      try {
        executor_->remove_node(node_);
      } catch (...) {
      }
    }
    executor_.reset();
    node_.reset();
    context_.reset();
  }

  uint64_t file_size(const std::string &path) {
    if (path.empty()) {
      return 0;
    }
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
      return 0;
    }
    return static_cast<uint64_t>(file.tellg());
  }

  std::mutex mutex_;
  std::string state_ = "stopped";
  std::string node_name_ = "android_phone_node";
  std::string qos_mode_ = "best_effort";
  std::string discovery_server_;
  std::string audio_file_path_;
  std::string audio_state_ = "idle";
  std::string last_command_;
  std::string last_error_;
  int domain_id_ = 0;
  double publish_rate_hz_ = 1.0;
  bool running_ = false;
  bool audio_receiving_ = false;
  bool audio_streaming_pcm_ = false;
  int audio_sample_rate_ = 16000;
  int audio_channels_ = 1;
  int audio_sample_width_ = 2;
  uint64_t published_count_ = 0;
  uint64_t received_count_ = 0;
  uint64_t audio_chunk_count_ = 0;
  uint64_t audio_transfer_count_ = 0;
  uint64_t audio_file_bytes_ = 0;
  uint64_t audio_pcm_bytes_ = 0;
  size_t audio_playback_queued_bytes_ = 0;

  std::shared_ptr<rclcpp::Context> context_;
  std::shared_ptr<rclcpp::Node> node_;
  std::shared_ptr<rclcpp::executors::SingleThreadedExecutor> executor_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr subscription_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr audio_control_subscription_;
  rclcpp::Subscription<std_msgs::msg::UInt8MultiArray>::SharedPtr audio_chunk_subscription_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr tx_audio_control_publisher_;
  rclcpp::Publisher<std_msgs::msg::UInt8MultiArray>::SharedPtr tx_audio_chunk_publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
  std::ofstream audio_stream_;
  std::deque<std::vector<uint8_t>> audio_playback_queue_;
  std::thread executor_thread_;
};

RosDemoRuntime g_runtime;

std::string to_string(JNIEnv *env, jstring value) {
  if (!value) {
    return {};
  }
  const char *chars = env->GetStringUTFChars(value, nullptr);
  std::string result = chars == nullptr ? "" : chars;
  if (chars != nullptr) {
    env->ReleaseStringUTFChars(value, chars);
  }
  return result;
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_ros2demo_NativeRosBridge_startSession(
    JNIEnv *env,
    jclass,
    jint domain_id,
    jstring node_name,
    jdouble publish_rate_hz,
    jstring qos_mode,
    jstring discovery_server,
    jstring audio_file_path) {
  return g_runtime.start(
      static_cast<int>(domain_id),
      to_string(env, node_name),
      static_cast<double>(publish_rate_hz),
      to_string(env, qos_mode),
      to_string(env, discovery_server),
      to_string(env, audio_file_path));
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_ros2demo_NativeRosBridge_stopSession(JNIEnv *, jclass) {
  g_runtime.stop();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_ros2demo_NativeRosBridge_sendUserCommand(JNIEnv *env, jclass, jstring command) {
  return g_runtime.send_local_command(to_string(env, command));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_ros2demo_NativeRosBridge_getSnapshotJson(JNIEnv *env, jclass) {
  std::string snapshot = g_runtime.snapshot();
  return env->NewStringUTF(snapshot.c_str());
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_ros2demo_NativeRosBridge_getAudioFileSize(JNIEnv *, jclass) {
  return static_cast<jlong>(g_runtime.audio_file_bytes());
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_ros2demo_NativeRosBridge_drainAudioPcm(JNIEnv *env, jclass) {
  std::vector<uint8_t> data = g_runtime.drain_audio_pcm();
  jbyteArray result = env->NewByteArray(static_cast<jsize>(data.size()));
  if (!data.empty()) {
    env->SetByteArrayRegion(
        result,
        0,
        static_cast<jsize>(data.size()),
        reinterpret_cast<const jbyte *>(data.data()));
  }
  return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_ros2demo_NativeRosBridge_publishTxAudioControl(
    JNIEnv *env, jclass, jstring command) {
  return g_runtime.publish_tx_audio_control(to_string(env, command));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_ros2demo_NativeRosBridge_publishTxAudioChunk(
    JNIEnv *env, jclass, jbyteArray data) {
  if (data == nullptr) {
    return JNI_FALSE;
  }
  jsize length = env->GetArrayLength(data);
  if (length <= 0) {
    return g_runtime.publish_tx_audio_chunk(nullptr, 0) ? JNI_TRUE : JNI_FALSE;
  }
  std::vector<uint8_t> buffer(static_cast<size_t>(length));
  env->GetByteArrayRegion(data, 0, length, reinterpret_cast<jbyte *>(buffer.data()));
  return g_runtime.publish_tx_audio_chunk(buffer.data(), buffer.size()) ? JNI_TRUE : JNI_FALSE;
}