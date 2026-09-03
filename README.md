# DYX_4WD

Clean production rewrite of the DYX 4WD rover software stack.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full specification.

**Status: Milestone 1 -- Architecture Skeleton.** Directory structure, package
skeletons, config/deployment/installer skeletons, and CI are in place. No
control logic, no `dyx_interfaces` message definitions, no PX4 DDS gateway
implementation, and no installer implementation yet.

## Layout

```text
backend/       Python backend (FastAPI + Socket.IO), no rclpy
ros2_ws/src/   C++ ROS2 production packages (ament_cmake only)
config/        Runtime parameters, grouped by owning package
deployment/    systemd units, network, udev, scripts
installer/     One-command install/upgrade/verify/uninstall
tools/         Analysis, bag, field, replay, migration utilities
docs/          Architecture, interfaces, safety, tuning, validation, migration
```

## Build

ROS2 workspace (requires ROS 2 Humble):

```bash
cd ros2_ws
colcon build
colcon test
```

Backend:

```bash
cd backend
pip install -e ".[dev]"
pytest tests
```
