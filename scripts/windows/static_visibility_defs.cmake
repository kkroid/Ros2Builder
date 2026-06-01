# ============================================================================
#  static_visibility_defs.cmake
#
#  Injected into every package of the Windows *static* ROS 2 build via
#  -DCMAKE_PROJECT_INCLUDE=<this file>. CMake runs it immediately after each
#  package's top-level project() call, so the definitions below are inherited
#  by every target in that package.
#
#  Why: ROS 2's visibility_control.h has no "static" branch. A package's
#  `<PKG>_PUBLIC` macro expands to `__declspec(dllimport)` unless the matching
#  `<PKG>_BUILDING_(DLL|LIBRARY)` macro is defined, and CMake only defines that
#  macro while building the package *itself*. So when a consumer (e.g. rclcpp)
#  compiles a *producer* header (rcl/rcutils/rmw) it sees `dllimport` and emits
#  `__imp_<sym>` references that do not exist in a static archive, producing
#  hundreds of LNK2019 at static-link time. On GCC/Clang `<PKG>_IMPORT` is
#  empty, so this is a Windows/MSVC-only problem (the Android static build links
#  cleanly without this).
#
#  Defining every core BUILDING macro globally makes producer headers always
#  resolve to `dllexport` (a direct, non-`__imp_` reference at the call site).
#  Defining a macro for a package whose headers a TU does not include is inert;
#  redefining a package's own macro is a harmless identical redefinition.
#
#  IMPORTANT: this uses add_compile_definitions() rather than setting
#  CMAKE_CXX_FLAGS, precisely so the MSVC default flags (notably /EHsc, which
#  Fast-DDS/boost require to avoid the BOOST_NO_EXCEPTIONS path and the
#  resulting unresolved boost::throw_exception) are preserved.
# ============================================================================
if(MSVC)
    add_compile_definitions(
        AMENT_INDEX_CPP_BUILDING_DLL
        LIBSTATISTICS_COLLECTOR_BUILDING_LIBRARY
        RCL_ACTION_BUILDING_DLL
        RCL_BUILDING_DLL
        RCL_LIFECYCLE_BUILDING_DLL
        RCL_LOGGING_INTERFACE_BUILDING_DLL
        RCL_YAML_PARAM_PARSER_BUILDING_DLL
        RCLCPP_ACTION_BUILDING_LIBRARY
        RCLCPP_BUILDING_LIBRARY
        RCLCPP_COMPONENTS_BUILDING_LIBRARY
        RCLCPP_LIFECYCLE_BUILDING_DLL
        RCPPUTILS_BUILDING_LIBRARY
        RCUTILS_BUILDING_DLL
        RMW_BUILDING_DLL
        RMW_DDS_COMMON_BUILDING_LIBRARY
        RMW_FASTRTPS_CPP_BUILDING_LIBRARY
        RMW_FASTRTPS_DYNAMIC_CPP_BUILDING_LIBRARY
        RMW_FASTRTPS_SHARED_CPP_BUILDING_LIBRARY
        RMW_IMPLEMENTATION_BUILDING_DLL
        ROSIDL_GENERATOR_C_BUILDING_DLL
        ROSIDL_TYPESUPPORT_C_BUILDING_DLL
        ROSIDL_TYPESUPPORT_CPP_BUILDING_DLL
        ROSIDL_TYPESUPPORT_FASTRTPS_C_BUILDING_DLL
        ROSIDL_TYPESUPPORT_FASTRTPS_CPP_BUILDING_DLL
        ROSIDL_TYPESUPPORT_INTROSPECTION_C_BUILDING_DLL
        ROSIDL_TYPESUPPORT_INTROSPECTION_CPP_BUILDING_DLL
        TRACETOOLS_BUILDING_DLL
    )

    # Per-message-package generator macros.
    #
    # Generated C message code (the `<pkg>__msg__*__init/__fini`,
    # `<pkg>__srv__*`, `<pkg>__action__*` functions emitted by
    # rosidl_generator_c) gates its visibility on the *suffixed* macro
    # `ROSIDL_GENERATOR_C_BUILDING_DLL_<pkg>` — distinct from the un-suffixed
    # core macro above. A consumer such as `<pkg>__rosidl_typesupport_*_c`
    # (and rcl, which uses rcl_interfaces/Log) that includes those generated
    # headers without the suffixed macro sees `dllimport` and emits
    # `__imp_<pkg>__msg__*`, which a static archive cannot satisfy. Define the
    # suffixed macro for every message package shipped in the static dist so
    # consumers emit direct references.
    add_compile_definitions(
        ROSIDL_GENERATOR_C_BUILDING_DLL_action_msgs
        ROSIDL_GENERATOR_C_BUILDING_DLL_builtin_interfaces
        ROSIDL_GENERATOR_C_BUILDING_DLL_rcl_interfaces
        ROSIDL_GENERATOR_C_BUILDING_DLL_rmw_dds_common
        ROSIDL_GENERATOR_C_BUILDING_DLL_rosgraph_msgs
        ROSIDL_GENERATOR_C_BUILDING_DLL_statistics_msgs
        ROSIDL_GENERATOR_C_BUILDING_DLL_std_msgs
        ROSIDL_GENERATOR_C_BUILDING_DLL_test_msgs
        ROSIDL_GENERATOR_C_BUILDING_DLL_unique_identifier_msgs
    )
endif()
