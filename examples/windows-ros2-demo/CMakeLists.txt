cmake_minimum_required(VERSION 3.20)

project(windows_ros2_demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WIN32)
  message(FATAL_ERROR "windows_ros2_demo only supports Windows.")
endif()

set(ROS2_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../work/windows/install/windows_x64" CACHE PATH "Path to Windows ROS 2 install prefix")
set(THIRD_PARTY_DIR "${CMAKE_CURRENT_LIST_DIR}/../../third_party/windows" CACHE PATH "Path to Windows third-party prefix")
get_filename_component(ROS2_PREFIX "${ROS2_PREFIX}" ABSOLUTE)
get_filename_component(THIRD_PARTY_DIR "${THIRD_PARTY_DIR}" ABSOLUTE)
if(NOT EXISTS "${ROS2_PREFIX}/setup.ps1")
  message(FATAL_ERROR "Missing ROS 2 Windows install prefix at ${ROS2_PREFIX}. Build Phase 2 first.")
endif()

list(APPEND CMAKE_PREFIX_PATH "${ROS2_PREFIX}" "${THIRD_PARTY_DIR}")
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)

set(IMGUI_DIR "${CMAKE_CURRENT_LIST_DIR}/third_party/imgui")
if(NOT EXISTS "${IMGUI_DIR}/imgui.cpp")
  message(FATAL_ERROR "Missing ImGui source at ${IMGUI_DIR}. Run scripts/fetch_imgui.ps1.")
endif()

cmake_path(CONVERT "${ROS2_PREFIX}" TO_CMAKE_PATH_LIST ROS2_PREFIX_DEFINE)

add_executable(windows_ros2_demo WIN32
  src/main.cpp
  src/audio_capturer.cpp
  src/ros_bridge.cpp
  src/wav_io.cpp
  ${IMGUI_DIR}/imgui.cpp
  ${IMGUI_DIR}/imgui_draw.cpp
  ${IMGUI_DIR}/imgui_tables.cpp
  ${IMGUI_DIR}/imgui_widgets.cpp
  ${IMGUI_DIR}/backends/imgui_impl_win32.cpp
  ${IMGUI_DIR}/backends/imgui_impl_dx11.cpp
)

target_include_directories(windows_ros2_demo PRIVATE
  src
  ${IMGUI_DIR}
  ${IMGUI_DIR}/backends
)

target_compile_definitions(windows_ros2_demo PRIVATE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
  _WIN32_WINNT=0x0A00
  ROS2_DIST_PATH="${ROS2_PREFIX_DEFINE}"
)

ament_target_dependencies(windows_ros2_demo rclcpp std_msgs)

target_link_libraries(windows_ros2_demo
  d3d11
  d3dcompiler
  dxgi
  comdlg32
  ole32
  uuid
  winmm
)

file(GLOB ROS2_RUNTIME_DLLS CONFIGURE_DEPENDS "${ROS2_PREFIX}/bin/*.dll" "${THIRD_PARTY_DIR}/bin/*.dll")
if(ROS2_RUNTIME_DLLS)
  add_custom_command(TARGET windows_ros2_demo POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${ROS2_RUNTIME_DLLS} $<TARGET_FILE_DIR:windows_ros2_demo>
    COMMAND_EXPAND_LISTS
  )
endif()