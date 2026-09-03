# ADR-0013: Compute platform — Jetson vs Radxa

- **Status:** **PROPOSED — undecided**
- **Date:** 2026-09-03
- **Spec:** not in V1 (V1 assumes "Jetson" throughout without justifying it)
- **Blocks:** Milestone 3. `os_check.sh`, udev rules, and network configuration all
  differ, and writing the installer against the wrong target means rewriting it.

## Context

V1 says "Jetson" everywhere, but never states why. The current architecture has **no
GPU workload**: no perception, no vision, no ML. Estimation is in PX4 (ADR-0005),
control is C++ on CPU, the backend is FastAPI. A Jetson's defining feature is unused.

## Options

### Option A — NVIDIA Jetson (Orin Nano / NX)

**Pros**
- Already in hand and already the development target
- CUDA available if vision or perception is ever added — camera-based line verification,
  obstacle detection, and ortho-based localisation are all plausible product directions
- Mature robotics ecosystem; most ROS 2 + PX4 companion guides assume Jetson
- Industrial carrier boards, wide temperature range, known thermal behavior
- Strong ecosystem of tested peripherals

**Cons**
- Significantly more expensive per unit — a real margin cost at production volume
- L4T/JetPack pins the kernel and often the Ubuntu release; upgrades lag upstream
- Kernel-level customisation is constrained by NVIDIA's BSP
- Higher power and more heat than the workload justifies
- Paying for silicon we do not use

### Option B — Radxa (Rock 5B / CM5 class)

**Pros**
- Substantially cheaper — matters directly at product volume
- Lower power, less heat, easier thermal design
- Mainline or near-mainline kernel support; less vendor lock on OS upgrades
- Ample CPU for this workload — the control graph is not compute-bound
- Good I/O for serial, Ethernet, and USB peripherals

**Cons**
- Smaller robotics ecosystem; fewer people have hit your problem before
- Vendor BSP quality varies by board and by revision
- No CUDA — forecloses GPU perception without a platform change
- Less field-proven in industrial deployments at this scale
- Peripheral support (particularly WiFi AP mode and 4G modems) needs verifying per board

### Option C — Decide later, keep the code portable

**Pros**
- Defers a decision that better information would improve
- Portability discipline is good anyway

**Cons**
- The installer, udev rules, and network config are exactly the platform-specific parts,
  and they are Milestone 3
- "Portable" in practice means "tested on neither"
- Deferring usually means deciding by accident

## Recommendation, pending your decision

Radxa if the product roadmap has no camera or perception work within about eighteen
months. The architecture as written does not need a GPU, and at volume the cost
difference is a margin line, not a rounding error.

Jetson if camera-based line verification, obstacle detection, or ortho-derived
localisation is on the roadmap. Migrating platforms after the installer, udev rules, and
field procedures are established costs far more than the unit price difference.

Either way, prove AP mode, the 4G modem, and the PX4 link (ADR-0014) on the chosen board
before writing the installer against it.

## Decide by

Before Milestone 3 (Installer V0).
