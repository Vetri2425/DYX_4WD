# ADR-0014: PX4 link transport — Ethernet vs serial

- **Status:** **PROPOSED — undecided**
- **Date:** 2026-09-03
- **Spec:** Sections 13, 22 (V1 assumes Ethernet)
- **Blocks:** Milestone 4, the timing contract, and the network topology document.

## Context

V1 specifies uXRCE-DDS over Ethernet on `192.168.10.0/24`. But **CubeOrange+ on the
standard and ADS-B carrier boards has no Ethernet port.** If the 4WD build uses that
flight controller, the Ethernet topology in Section 22 does not exist and the DDS link
runs over serial.

This is not a preference. It is a hardware fact that has to be checked, and it changes
the timing budget, the failure modes, and the platform service.

## Options

### Option A — uXRCE-DDS over Ethernet

**Pros**
- High throughput; setpoint rate is not transport-limited
- Lower and more consistent latency — directly relevant to the cm accuracy budget
- Standard networking tools for diagnosis (`ping`, `tcpdump`, `iperf`)
- Room to grow: more telemetry topics without hitting a ceiling
- Clean separation as its own network interface

**Cons**
- Requires a carrier board with Ethernet — a hardware decision, possibly a purchase
- More configuration: static IPs on both ends, PX4 `netman`, link-loss behavior
- One more physical connector to survive vibration and weather

### Option B — uXRCE-DDS over serial (TELEM2)

**Pros**
- Works with the CubeOrange+ hardware likely already in hand
- Simple, well-understood physical link
- Fewer moving parts; no IP configuration on the PX4 side
- Robust connector

**Cons**
- **Baud rate is a hard ceiling on setpoint and telemetry rate.** At 921600 baud the
  budget is tight once vehicle state, status, and setpoints share the link
- Higher and more variable latency than Ethernet
- Forces choices about which topics to carry — telemetry competes with control
- Harder to diagnose; no standard tooling equivalent to `tcpdump`
- Constrains the timing contract before the controller is even written

## What this changes downstream

| | Ethernet | Serial |
|---|---|---|
| `dyx-platform` | `MicroXRCEAgent udp4 -p 8888` | `MicroXRCEAgent serial --dev /dev/ttyTHS1 -b 921600` |
| Network topology | `eth0` 192.168.10.0/24 exists | no PX4 network plane |
| Timing contract | bounded by processing | bounded by baud rate |
| udev | — | stable symlink for the serial device required |
| Failure mode | link down, detectable | silent corruption, framing errors |

## Recommendation

Confirm the actual carrier board first — this may not be a choice at all.

If Ethernet is available, take it. The accuracy target makes transport latency a
first-order concern, and serial's baud ceiling constrains the controller before it is
written.

If the hardware is fixed at serial, that is workable, but the topic set carried over the
link must be budgeted explicitly and the timing contract written against the measured
rate rather than an assumed one.

## Decide by

Before Milestone 4. This is the first thing Milestone 4 should establish.
