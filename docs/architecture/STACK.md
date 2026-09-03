# Stack Details — DYX 4WD

Layer-by-layer account of what we run, why, and what we rejected. Decisions with real
argument behind them get their own ADR; this document is the map.

---

## The requirement that drives everything

Centimetre cross-track accuracy and sub-degree heading stability, on construction
ground, loose soil, solar fields, gravel, mud, and slopes.

Two consequences fall out immediately and explain most of the stack:

**Latency is distance.** At 0.8 m/s, 25 ms of control latency is 2 cm of lag. Every
process hop, every serialization, every scheduler delay converts directly into error.
This is why the control plane is C++ (ADR-0002), why MAVROS is gone (ADR-0003), and why
the transport question is not cosmetic (ADR-0014).

**Terrain makes geometry dominate.** An antenna 1.2 m up at 5° roll displaces the
reported position ~10 cm laterally. Estimation quality and mechanical measurement
matter as much as controller tuning (ADR-0005, ADR-0015).

---

## Layer 1 — Flight controller and firmware

**PX4 v1.17 on CubeOrange+ (transport TBD — ADR-0014)**

PX4 owns: IMU and GNSS processing, EKF2, attitude and position estimation, yaw-rate and
speed inner loops, differential allocation, actuator output, hardware failsafes.

PX4 does **not** own: active waypoint, path shape, cross-track correction, pivot
strategy, terminal strategy, mission completion. Those live above it (ADR-0004).

**Why PX4 rather than a custom controller:** a mature, field-proven EKF with dual-antenna
GNSS heading and lever-arm compensation is years of work. The rover module's inner loops
and failsafes are already there. Writing our own would mean rediscovering known failure
modes on hardware that moves.

**What it costs:** estimator tuning happens in PX4 parameters, outside the ROS parameter
architecture (ADR-0005). Firmware upgrades are contract changes (ADR-0003).

---

## Layer 2 — PX4 ↔ ROS transport

**uXRCE-DDS with `px4_msgs`. No MAVROS.** — ADR-0003

Direct uORB access, no MAVLink translation. The version lock is the price: `px4_msgs`
must match firmware exactly or deserialization is silently wrong.

`docs/interfaces/px4_contract_v1.md` is what makes this survivable — it pins topics,
message SHAs, and the PX4 parameters that form the contract.

---

## Layer 3 — ROS 2 control graph

**ROS 2 Humble, all C++, `ament_cmake`** — ADR-0002

Eleven packages, each owning exactly one decision (Section 29):

| Package | Owns |
|---|---|
| `dyx_interfaces` | shared message/service/action contracts |
| `dyx_trajectory` | path geometry — what path to follow |
| `dyx_mission` | mission state — which target is active |
| `dyx_rpp` | path-following decision — how to move |
| `dyx_motion_control` | command validity and safety gating |
| `dyx_px4_gateway` | ROS↔PX4 transport |
| `dyx_rtk` | correction delivery |
| `dyx_spray` | marking actuator execution |
| `dyx_system_gateway` | backend↔ROS boundary |
| `dyx_recorder` | field evidence |
| `dyx_bringup` | launch authority |

**Why ROS 2 rather than a bespoke framework:** DDS discovery, typed interfaces, bag
recording, parameter services, and the introspection tooling would all have to be
rebuilt. `rosbag2` alone justifies it — the entire migration strategy (ADR-0001) runs on
recorded evidence.

**Why Humble rather than Jazzy:** matches the existing stack and the Jetson's Ubuntu
22.04. Jazzy is the eventual move, not a now move.

**Design constraint worth repeating:** algorithm modules inside `dyx_rpp` contain no
`rclcpp`. Pure C++ on plain structs, testable on a laptop in seconds. Only `rpp_node.cpp`
touches ROS. This is what keeps C++ iteration tolerable.

---

## Layer 4 — Control ownership

**RPP emits explicit intent; PX4 executes it** — ADR-0004

One canonical `MotionSetpoint` with a mode: `STOP`, `SPEED_HEADING`, `SPEED_RATE`,
`PIVOT_RATE`. Replaces the old XY velocity vector from which PX4 inferred rotation.

**Open:** whether `SPEED_HEADING` should be used during marking at all, or whether
heading should close inside RPP so tracking uses a single mode. Mode transitions are an
oscillation source, and oscillation is the thing we are trying to eliminate. See OQ-1.

---

## Layer 5 — Safety

Safety lives **below** the backend. A GCS stop is a request, not authority.

```
GCS request → System Gateway → Mission state → Motion Control → PX4 Gateway → PX4
```

`dyx_motion_control` gates on: command freshness, finite values, mission state, E-stop,
speed/yaw-rate/acceleration limits, sequence validity, estimator health. Every failure
path ends at `speed = 0, yaw_rate = 0, mode = STOP`. Never "hold last command."

**A physical E-stop, wired independently of the Jetson, is required.** No software path
substitutes for it, and no button in the GCS should be labelled as though it does.

---

## Layer 6 — Backend

**Python, FastAPI + Socket.IO, no `rclpy`** — ADR-0008

Owns the external API, auth, mission upload, telemetry delivery, storage, settings. It
reaches ROS only through `dyx_system_gateway` over local IPC.

**Why Python here and nowhere else:** HTTP, serialization, auth, and storage are what
Python is good at, and none of it is in the control path. The boundary is structural —
the backend cannot publish to a control topic, so whether it should is not a recurring
review question.

---

## Layer 7 — Client

**React Native GCS over WiFi, BLE for provisioning**

BLE carries identity, link status, AP credentials, and a low-bandwidth stop request.
WiFi carries everything real: mission upload, telemetry, live map, parameter tuning.

BLE bandwidth cannot carry telemetry. Do not try.

---

## Layer 8 — Network

**Jetson is the access point; no router** — ADR-0012

Three separated planes: PX4 control (`192.168.10.0/24`, never bridged), client AP
(`192.168.20.0/24`), and 4G WAN carrying the only default route.

Full detail in `docs/deployment/network_topology.md`.

---

## Layer 9 — Configuration and tuning

**Three parameter classes, validated and audited** — ADR-0009

`LIVE` applies immediately. `IDLE_ONLY` is refused during a mission, with a reason.
`RESTART_REQUIRED` covers infrastructure — addresses, transports, ports, paths.

Every change is recorded: timestamp, node, parameter, old, new, source, mission,
accepted/rejected. This is what lets a field bag answer "what was active at this moment"
without guessing, which is what makes bags evidence rather than anecdote.

---

## Layer 10 — Deployment

**Versioned release artifact, symlink switch, rollback** — ADR-0010

```
/opt/dyx/releases/<version>/    /opt/dyx/current -> <version>
/etc/dyx/                       config, survives upgrade and rollback
/var/lib/dyx/                   missions, runs, bags, state
```

Four systemd services (ADR-0007): `dyx-platform` → `dyx-ros` → `dyx-backend` +
`dyx-recorder`. The rover reaches READY after boot with no SSH session.

`dyx-version`, `dyx-health`, `dyx-param` are the field interface.

---

## Layer 11 — Evidence

**Recorder is a production component** — ADR-0011

Every run produces a directory containing the bag plus manifest, git versions, config
snapshot, mission, and summary. A run without provenance is incomplete evidence.

This is load-bearing: bag replay comparison and shadow validation are the migration
strategy, and they only work if bags are trustworthy.

---

## Development environment

| | Where | Authoritative? |
|---|---|---|
| Pure module tests | plain CMake + gtest, any machine | yes, for logic |
| ROS build/test | micromamba (macOS) or container | no |
| ROS build/test | CI on `ubuntu-24.04-arm` | **yes** |
| Timing, DDS, systemd, installer | target hardware only | **yes** |

macOS builds are for iteration speed. Never report timing, DDS, or deployment behavior
as verified from a laptop.

---

## What is not decided

| Question | ADR | Blocks |
|---|---|---|
| Jetson or Radxa | 0013 | Milestone 3 |
| Ethernet or serial to PX4 | 0014 | Milestone 4 |
| Nozzle as control point | 0015 | accuracy spec |
| `SPEED_HEADING` during marking | 0004 OQ-1 | RPP port |

These are listed together because they share a property: each is cheap to decide now and
expensive to discover later. All four are answered by Milestone 4 hardware bring-up plus
one mechanical measurement session.
