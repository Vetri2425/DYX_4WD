# Network Topology — DYX 4WD

Status: DRAFT — addresses below are proposals until confirmed on hardware.
Implements Section 22 of the architecture document.

There is **no router on the rover.** The Jetson is the access point, the DHCP server,
and the only routed device. Everything else is a client.

---

## 1. Topology

```text
                    ┌──────────────────────────┐
   PX4 / CubeOrange │                          │
   192.168.10.1     │   eth0   192.168.10.2/24 │
   ─────────────────┤          (PX4 only)      │
                    │                          │
   MacBook (dev)    │                          │
   Tablet / RN GCS  │  wlan0   192.168.20.1/24 │
   ─────────────────┤          AP + DHCP       │   JETSON
   BLE (GCS pairing)│  hci0    GATT peripheral │
   ─────────────────┤                          │
                    │                          │
   NTRIP / remote   │  usb0/wwan0   DHCP       │
   ─────────────────┤          4G, default rt  │
                    └──────────────────────────┘
```

Three separated planes:

| Plane | Interface | Subnet | Carries |
|---|---|---|---|
| Control | `eth0` | `192.168.10.0/24` | uXRCE-DDS to PX4. Nothing else. |
| Client | `wlan0` (AP) | `192.168.20.0/24` | REST + Socket.IO, SSH, ROS debug |
| WAN | `usb0` / `wwan0` | DHCP from dongle | NTRIP corrections, remote access |

**The control plane is never bridged to the client or WAN planes.** No IP forwarding
between `wlan0` and `eth0`. A tablet must not be able to reach PX4.

---

## 2. Addressing

| Device | Address | Assignment |
|---|---|---|
| PX4 | `192.168.10.1` | static, PX4 `netman` config |
| Jetson `eth0` | `192.168.10.2` | static |
| Jetson `wlan0` | `192.168.20.1` | static, gateway for clients |
| MacBook | `192.168.20.10–.99` | DHCP |
| Tablet / GCS | `192.168.20.10–.99` | DHCP |
| Reserved | `192.168.20.100–.199` | static leases by MAC |

Hostname `dyx-jetson.local` via Avahi so the Mac can reach the rover without memorizing
the address.

**Verify before implementing:** many 4G dongles default to `192.168.8.0/24` (Huawei) or
`192.168.1.0/24`. If your dongle uses `192.168.10.x` or `192.168.20.x`, one of these
subnets must move. Check with `ip addr` on first connection.

---

## 3. PX4 link — confirm the transport first

The architecture assumes uXRCE-DDS over Ethernet. **CubeOrange+ on the standard and
ADS-B carrier boards has no Ethernet port.** If the 4WD build uses one of those, the
DDS link runs over serial (TELEM2) instead, and `eth0` above does not exist.

This must be settled before Milestone 4 and recorded in
`docs/interfaces/px4_contract_v1.md`. The two paths differ in throughput, latency, and
failure modes, and the timing contract depends on which one is real.

**Ethernet path:**
```bash
MicroXRCEAgent udp4 -p 8888
```
PX4 params: `MAV_1_CONFIG`, `XRCE_DDS_0_CFG`, plus `netman` static IP.

**Serial path:**
```bash
MicroXRCEAgent serial --dev /dev/ttyTHS1 -b 921600
```
Baud rate becomes a hard constraint on setpoint rate — factor it into the timing budget.

Either way the agent is owned by `dyx-platform.service` and must be up before
`dyx-ros.service` starts.

---

## 4. Jetson hotspot

NetworkManager, created once by the installer:

```bash
nmcli con add type wifi ifname wlan0 con-name dyx-ap autoconnect yes ssid DYX-ROVER-01
nmcli con modify dyx-ap 802-11-wireless.mode ap 802-11-wireless.band bg
nmcli con modify dyx-ap ipv4.method shared ipv4.addresses 192.168.20.1/24
nmcli con modify dyx-ap wifi-sec.key-mgmt wpa-psk
nmcli con modify dyx-ap wifi-sec.psk "$DYX_AP_PSK"
nmcli con modify dyx-ap connection.autoconnect-priority 100
```

`ipv4.method shared` gives DHCP and DNS on `192.168.20.0/24`.

The PSK comes from `/etc/dyx/network.env` (`root:dyx`, `0640`). **Never in Git.**
Per-rover SSID (`DYX-ROVER-01`, `-02`) so two rovers on one site don't collide.

Use 2.4 GHz for range through equipment and bodies; 5 GHz if the site is congested and
the tablet stays close. Pick one and record it — it affects field range, which affects
how far the operator can stand from a moving machine.

---

## 5. 4G WAN and routing

The dongle provides the **only** default route. This is where routing usually breaks.

```bash
# WAN wins for default route
nmcli con modify dyx-wan ipv4.route-metric 100
# AP must never be a default route
nmcli con modify dyx-ap  ipv4.never-default yes
# Control plane is link-local only
nmcli con modify dyx-eth ipv4.never-default yes ipv4.ignore-auto-dns yes
```

Verify:
```bash
ip route show          # exactly one default, via usb0/wwan0
ping -c1 -I eth0 192.168.10.1
curl -s --interface usb0 https://example.com -o /dev/null -w '%{http_code}\n'
```

NTRIP corrections (`dyx_rtk`) depend on this path. Correction loss must degrade RTK
status cleanly, never stall the control loop — `dyx_motion_control` handles the
consequence, not the RTK node.

GSM modules (SIM7600 and similar) come up as `wwan0` via QMI/ModemManager, or `ppp0` via
PPP. Prefer ModemManager — it reconnects on signal loss without supervision. Put the
APN in `/etc/dyx/network.env`.

`dyx-platform.service` should not block startup on WAN. The rover must reach READY and
be drivable with no signal; RTK simply reports degraded.

---

## 6. MacBook access from home and field

Join `DYX-ROVER-01`, then:

```bash
ssh dyx@dyx-jetson.local        # or 192.168.20.1
```

**Expect no internet on the Mac while joined.** One WiFi radio, and the rover AP is not
an uplink. Two ways around it:

- USB-C Ethernet adapter for internet, WiFi for the rover. Confirm macOS service order
  puts Ethernet above WiFi.
- Tailscale on the Jetson over the 4G link — then reach the rover from home over the
  dongle without joining the hotspot at all. This is the better answer for working from
  the MacBook at home, and worth setting up early.

Disable macOS auto-join on the rover SSID or it will drift back to your home network
mid-session.

ROS 2 debugging from the Mac across the hotspot is possible but not recommended — DDS
discovery over WiFi is noisy and can perturb the very timing you are measuring. Prefer
recording a bag on the rover and analysing it afterward.

---

## 7. React Native client — BLE and WiFi

Two channels with different jobs. Do not use one for the other's work.

**BLE — provisioning and presence.** Always available, no network needed. Used to
discover the rover, read its identity and health, hand over WiFi credentials, and
confirm the AP is up. GATT peripheral on the Jetson (BlueZ), advertising a DYX service:

| Characteristic | Access | Purpose |
|---|---|---|
| Rover ID / serial | read | identify before connecting |
| AP SSID | read | so the app can join automatically |
| Link status | notify | AP up, backend up, PX4 connected, RTK fix |
| Battery / health | notify | pre-connection check |
| Stop request | write | low-bandwidth fallback |

**WiFi — everything real.** REST and Socket.IO to the backend on `192.168.20.1`.
Mission upload, telemetry, live map, parameter tuning. BLE bandwidth cannot carry
telemetry; do not try.

**Stop over BLE is a request, not authority.** Section 23 is unconditional: final motion
authority is `dyx_motion_control` and PX4. A BLE stop enters through the same path as a
backend stop and is subject to the same gating. It is not, and must never be presented
to the operator as, a hardware emergency stop. The rover needs a physical E-stop
independent of all of this.

Pair once over BLE, hand over credentials, switch to WiFi, keep BLE connected as a
liveness channel — that is the intended flow.

---

## 8. Field checklist

```text
1. Power up. Jetson AP appears within ~40 s.
2. Tablet: BLE discovers rover → reads SSID → joins WiFi.
3. Confirm backend health at http://192.168.20.1:<port>/health
4. Confirm PX4 link: ping 192.168.10.1 (or DDS agent log on serial)
5. Confirm 4G: one default route, NTRIP connected
6. Confirm RTK FIXED before arming
7. Physical E-stop tested before every session
```

Any step failing means the rover does not run. The health check exists so this is one
command (`dyx-health`), not seven.
