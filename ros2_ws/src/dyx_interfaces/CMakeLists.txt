cmake_minimum_required(VERSION 3.16)
project(dyx_interfaces)

find_package(ament_cmake REQUIRED)

# Milestone 1 skeleton: no build targets yet.
# add_library()/add_executable() are added once this package's contract
# (docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md) is implemented.

if(BUILD_TESTING)
  find_package(ament_cmake_gtest REQUIRED)
  # ament_add_gtest(<test_name> test/<test_file>.cpp) goes here once tests exist.
endif()

ament_package()
