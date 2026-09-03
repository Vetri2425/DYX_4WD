# ADR-0012: Jetson is the access point; no router on the rover

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Section 22

## Context

The rover works on sites with no infrastructure. There is no WiFi to join and often no
reason to expect one. The operator carries a tablet running the React Native GCS. RTK
corrections arrive over a 4G dongle or GSM module with a SIM.

Something has to provide a network for the tablet.

## Decision

The Jetson is the access point. `wlan0` runs in AP mode on `192.168.20.0/24` with DHCP.
PX4 is on a separate `192.168.10.0/24` link that is never bridged to the client network.
The 4G interface carries the only default route. BLE provides discovery and provisioning
before WiFi is up.

## Alternatives considered

### Option A — Small travel router on the rover

**Pros**
- Better radio, better antenna, better range than a Jetson's onboard WiFi
- Offloads AP duty from the compute module
- Can handle 4G, AP, and routing in one purpose-built device
- Replaceable in the field without touching the compute stack

**Cons**
- Another device to power, mount, weatherproof, and configure
- Another failure point, with its own firmware and its own config drift
- Its configuration lives outside our installer, so rover-to-rover consistency is manual
- Cost and space on a machine that is already dense

### Option B — Jetson as AP *(chosen)*

**Pros**
- Fewer parts; nothing to mount or power separately
- Network configuration is owned by our installer and therefore reproducible
- One place to debug; `dyx-health` can report the whole network state
- No inter-device dependency at boot

**Cons**
- Onboard WiFi antennas are typically worse than a router's — range is the real cost,
  and range means how far an operator can stand from a moving machine
- If the Jetson is unhealthy, the operator loses their view of it at the same moment
- No roaming, no mesh, one radio
- AP mode plus DDS traffic on the same CPU

### Option C — MAVLink telemetry radio for GCS

**Pros**
- Long range, purpose-built for this
- Independent of the compute module

**Cons**
- Bandwidth cannot carry the telemetry and map data the React Native GCS needs
- Reintroduces a MAVLink path we removed in ADR-0003

## Why we chose what we chose

Reproducibility. A travel router's configuration cannot be owned by `install.sh`, which
means every rover's network is set up by hand and drifts. Given that the installer is a
core requirement (ADR-0010), keeping the network inside its scope is worth the antenna
penalty.

## Consequences

**We accept:** shorter WiFi range than dedicated hardware, and losing the operator's
view if the Jetson is unhealthy.

**We must therefore:**
- Keep BLE as an independent channel. When WiFi is unavailable, BLE still reports rover
  identity and link status
- Provide a **physical E-stop** wired independently of the Jetson. A GCS stop over WiFi
  or BLE is a request routed through the same gating as any other (Section 23), and must
  never be presented to an operator as an emergency stop
- Enforce network separation: no IP forwarding between `wlan0` and `eth0`; the tablet
  must not reach PX4
- Discipline the default route — only the 4G interface carries one, or NTRIP silently
  fails
- Measure actual field range early. If it is inadequate, Option A returns as a
  deliberate trade

**Revisit if:** measured range is insufficient for safe operator standoff. That is a
safety finding, and it outranks configuration reproducibility.
