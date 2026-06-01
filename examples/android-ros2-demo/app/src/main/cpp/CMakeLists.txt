cmake_minimum_required(VERSION 3.22.1)

project(ros2_android_demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ROS2_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../ros2/include")
set(ROS2_STATIC_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/../ros2/lib/${ANDROID_ABI}")
set(ROS2_JNILIB_DIR "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}")

if(NOT EXISTS "${ROS2_INCLUDE_DIR}")
  message(FATAL_ERROR "Missing ROS 2 headers: ${ROS2_INCLUDE_DIR}. Run scripts/sync_ros2_artifacts first.")
endif()

if(NOT EXISTS "${ROS2_JNILIB_DIR}")
  message(FATAL_ERROR "Missing ROS 2 shared libraries: ${ROS2_JNILIB_DIR}. Run scripts/sync_ros2_artifacts first.")
endif()

file(GLOB ROS2_SHARED_LIBS CONFIGURE_DEPENDS "${ROS2_JNILIB_DIR}/*.so")
file(GLOB ROS2_STATIC_LIBS CONFIGURE_DEPENDS "${ROS2_STATIC_LIB_DIR}/*.a")
# Defense in depth: drop packages/libs the audio demo does not use, even if the
# sync step copied them. Keep in sync with scripts/sync_ros2_artifacts.{ps1,sh}.
list(FILTER ROS2_STATIC_LIBS EXCLUDE REGEX ".*/(librmw_fastrtps_cpp|libaction_msgs__.*|libunique_identifier_msgs__.*|libtest_msgs__.*|librcl_logging_spdlog)\\.a$")
file(GLOB ROS2_PACKAGE_INCLUDE_DIRS CONFIGURE_DEPENDS LIST_DIRECTORIES true "${ROS2_INCLUDE_DIR}/*")
set(ROS2_IMPORTED_TARGETS "")

if(NOT ROS2_SHARED_LIBS AND NOT ROS2_STATIC_LIBS)
  message(FATAL_ERROR "Missing ROS 2 libraries. Run scripts/sync_ros2_artifacts first.")
endif()

foreach(ROS2_SHARED_LIB IN LISTS ROS2_SHARED_LIBS)
  get_filename_component(ROS2_SHARED_NAME "${ROS2_SHARED_LIB}" NAME_WE)
  string(REGEX REPLACE "[^A-Za-z0-9_]" "_" ROS2_TARGET_SUFFIX "${ROS2_SHARED_NAME}")
  set(ROS2_TARGET "ros2_prebuilt_${ROS2_TARGET_SUFFIX}")
  add_library("${ROS2_TARGET}" SHARED IMPORTED)
  set_target_properties("${ROS2_TARGET}" PROPERTIES IMPORTED_LOCATION "${ROS2_SHARED_LIB}")
  list(APPEND ROS2_IMPORTED_TARGETS "${ROS2_TARGET}")
endforeach()

add_library(ros2_android_demo SHARED native_bridge.cpp)

target_include_directories(ros2_android_demo PRIVATE
  "${ROS2_INCLUDE_DIR}"
  ${ROS2_PACKAGE_INCLUDE_DIRS}
)

target_link_libraries(ros2_android_demo PRIVATE
  -Wl,--whole-archive
  -Wl,--start-group
  ${ROS2_STATIC_LIBS}
  -Wl,--end-group
  -Wl,--no-whole-archive
  ${ROS2_IMPORTED_TARGETS}
  log
  android
)