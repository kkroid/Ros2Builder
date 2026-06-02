cmake_minimum_required(VERSION 3.8)
project(ais_node_interface)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(std_msgs REQUIRED)
find_package(builtin_interfaces REQUIRED)

rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/AudioCapture.msg"
  "msg/AudioInfo.msg"
  "msg/AudioData.msg"
  "msg/ImageMsg.msg"
  "msg/WakeEvent.msg"
  "msg/DoaMsg.msg"
  "msg/AsrResult.msg"
  "msg/FaceFeature.msg"
  "msg/FaceFeatureArray.msg"
  "msg/GestureEvent.msg"
  "msg/DmOutput.msg"
  "msg/AiStatus.msg"
  "msg/KwsEvalResult.msg"
  "msg/FaceIdResult.msg"
  "srv/Session.srv"
  "srv/Wakeup.srv"
  "srv/Dialog.srv"
  "srv/Tts.srv"
  "srv/FaceId.srv"
  DEPENDENCIES std_msgs builtin_interfaces
)

ament_export_dependencies(rosidl_default_runtime)
ament_package()
