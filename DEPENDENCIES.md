# ROS 2 Humble Android dependency check

目标是 Android `arm64-v8a` 的 ROS 2 Humble C/C++ 动态库。这里把“ROS 包名”和“GitHub 仓库”分开列，源码版本以官方 `ros2/ros2` 的 Humble `ros2.repos` 为准。

## 需要修正的点

- `rosenv` 应改为 `ros_environment`，仓库是 `ros/ros_environment`。
- `FastRTPS` 是旧称。Humble 里源码仓库按 `eProsima/Fast-DDS`，CMake 包/库仍常见 `fastrtps` 这个名字。
- 最小 8 项清单不够完整。`rclcpp`、`std_msgs` 和 `rmw_fastrtps_cpp` 会引入 rosidl、rmw、rcl_interfaces、Fast CDR、Fast DDS、foonathan memory 等依赖。
- `pcre2_vendor` 不在官方 Humble `ros2.repos` 核心清单里。除非你的上层包明确依赖它，否则不要先放进 Android 最小集。
- 不建议手工按文本顺序逐个编译。用 `colcon --packages-up-to ...`，让 colcon 按包依赖拓扑顺序编译。
- `nav_msgs` 在 Humble 对应 `ros-planning/navigation_msgs`，不是 `ros2/common_interfaces`。

## 核心层

| 功能 | ROS 包 | GitHub 仓库 | Humble 版本 |
| --- | --- | --- | --- |
| ament 构建 | `ament_cmake` | `https://github.com/ament/ament_cmake.git` | `humble` |
| ament package 元数据 | `ament_package` | `https://github.com/ament/ament_package.git` | `humble` |
| ament 索引 | `ament_index_cpp` | `https://github.com/ament/ament_index.git` | `humble` |
| 环境钩子 | `ros_environment` | `https://github.com/ros/ros_environment.git` | `humble` |
| C 基础库 | `rcutils` | `https://github.com/ros2/rcutils.git` | `humble` |
| C++ 基础库 | `rcpputils` | `https://github.com/ros2/rcpputils.git` | `humble` |
| YAML C vendor | `libyaml_vendor` | `https://github.com/ros2/libyaml_vendor.git` | `humble` |
| TinyXML2 vendor | `tinyxml2_vendor` | `https://github.com/ros2/tinyxml2_vendor.git` | `humble` |
| RCL | `rcl`, `rcl_action`, `rcl_lifecycle`, `rcl_yaml_param_parser` | `https://github.com/ros2/rcl.git` | `humble` |
| RCL 日志 | `rcl_logging_interface`, `rcl_logging_spdlog` | `https://github.com/ros2/rcl_logging.git` | `humble` |
| spdlog vendor | `spdlog_vendor` | `https://github.com/ros2/spdlog_vendor.git` | `humble` |
| C++ 客户端库 | `rclcpp`, `rclcpp_action`, `rclcpp_components`, `rclcpp_lifecycle` | `https://github.com/ros2/rclcpp.git` | `humble` |
| 组件加载 | `class_loader` | `https://github.com/ros/class_loader.git` | `humble` |
| pluginlib | `pluginlib` | `https://github.com/ros/pluginlib.git` | `humble` |
| console bridge vendor | `console_bridge_vendor` | `https://github.com/ros2/console_bridge_vendor.git` | `humble` |
| RMW 抽象 | `rmw`, `rmw_implementation` | `https://github.com/ros2/rmw.git`, `https://github.com/ros2/rmw_implementation.git` | `humble` |
| Fast DDS RMW | `rmw_fastrtps_cpp`, `rmw_fastrtps_shared_cpp`, `rmw_fastrtps_dynamic_cpp` | `https://github.com/ros2/rmw_fastrtps.git` | `humble` |
| DDS 公共类型 | `rmw_dds_common` | `https://github.com/ros2/rmw_dds_common.git` | `humble` |
| Fast DDS | `fastrtps` | `https://github.com/eProsima/Fast-DDS.git` | `2.6.x` |
| Fast CDR | `fastcdr` | `https://github.com/eProsima/Fast-CDR.git` | `v1.0.24` |
| foonathan memory | `foonathan_memory_vendor` | `https://github.com/eProsima/foonathan_memory_vendor.git` | `master` |
| rosidl 生成链 | `rosidl_*` | `https://github.com/ros2/rosidl.git`, `https://github.com/ros2/rosidl_typesupport.git`, `https://github.com/ros2/rosidl_typesupport_fastrtps.git` | `humble` |

## 消息层

| ROS 包 | GitHub 仓库 | 说明 |
| --- | --- | --- |
| `std_msgs`, `sensor_msgs`, `geometry_msgs` | `https://github.com/ros2/common_interfaces.git` | 标准消息主体 |
| `nav_msgs` | `https://github.com/ros-planning/navigation_msgs.git` | 导航消息 |
| `builtin_interfaces`, `action_msgs`, `rosgraph_msgs`, `service_msgs`, `statistics_msgs` | `https://github.com/ros2/rcl_interfaces.git` | RCL/动作/服务基础接口 |
| `unique_identifier_msgs` | `https://github.com/ros2/unique_identifier_msgs.git` | 动作和 UUID 相关接口 |

## 扩展层

| 功能 | ROS 包 | GitHub 仓库 | Android 风险 |
| --- | --- | --- | --- |
| TF2 | `tf2`, `tf2_ros`, `tf2_msgs` | `https://github.com/ros2/geometry2.git` | 中等 |
| message_filters | `message_filters` | `https://github.com/ros2/message_filters.git` | 低到中等 |
| image_transport | `image_transport`, `camera_info_manager` | `https://github.com/ros-perception/image_common.git` | 中等，插件和图像链要单独验证 |
| rosbag2 | `rosbag2_cpp`, `rosbag2_storage`, `rosbag2_transport` | `https://github.com/ros2/rosbag2.git` | 高，存储插件、sqlite/压缩/文件系统细节需要逐项处理 |

## 建议的构建范围

第一阶段验证：

```bash
BUILD_PACKAGES="rclcpp rmw_fastrtps_cpp std_msgs"
```

第二阶段加入常用消息：

```bash
BUILD_PACKAGES="rclcpp rmw_fastrtps_cpp std_msgs sensor_msgs geometry_msgs nav_msgs"
```

第三阶段再加入功能库：

```bash
BUILD_PACKAGES="tf2_ros image_transport"
```

`rosbag2` 建议最后单独处理，不要和最小通信链路一起排错。