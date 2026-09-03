# Architecture

This repository is the clean production rewrite of the DYX 4WD rover stack: C++
ROS2 control nodes talking to PX4 directly over DDS (no MAVROS), a Python-only
backend with no `rclpy`, clean systemd service separation, and a one-command
production installer. RPP owns path-level speed and rotational intent; PX4 owns
estimation and the inner physical control loops.

The full specification -- repository structure, package authorities and
boundaries, control modes, systemd/network/parameter architecture, the
production installer, and the migration order from `rover_ws` -- lives in:

**[docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md](docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md)**

This file is a pointer only. Do not duplicate the V1 document's content here --
if something needs to change, change the source-of-truth document.
