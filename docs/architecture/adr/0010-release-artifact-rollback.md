# ADR-0010: Release artifacts, /opt/dyx filesystem, and rollback

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 39–50

## Context

A production rover is installed by whoever is on site, not by the engineer who wrote
the code. Today, standing up a Jetson means hours of manual apt installs, service file
copying, permission fixing, and network configuration — none of it reproducible, all of
it undocumented except in someone's memory.

Separately: when an update breaks a rover in a field two hours from the office, the
recovery path matters more than the update did.

## Decision

CI produces one versioned artifact (`dyx-4wd-<version>-arm64.tar.zst`). The installer
places releases under `/opt/dyx/releases/<version>/` with `/opt/dyx/current` as a
symlink. Runtime data lives in `/var/lib/dyx/`, configuration in `/etc/dyx/`. Upgrade
verifies before switching the symlink; the previous release stays for `dyx-rollback`.

## Alternatives considered

### Option A — Build from source on the rover (status quo)

**Pros**
- No CI or artifact infrastructure needed
- Whatever is on the rover is inspectable and patchable in place
- One workflow for development and production

**Cons**
- Compiling a ROS 2 workspace on a Jetson is slow, and slow at the worst moment
- Not reproducible: the binary depends on whatever apt state that machine happens to have
- Compilers and headers on a production machine
- No rollback — recovery means `git checkout` and another slow build
- No way to answer "is this rover running the same software as that rover"

### Option B — Container images on the rover

**Pros**
- Reproducible and atomic; rollback is re-tagging
- Same image in CI and production
- Dependency isolation

**Cons**
- Device access (serial, GPIO, network interfaces) needs privileged containers, eroding
  the isolation that motivated it
- Another runtime to install, supervise, and debug in the field
- Interacts awkwardly with systemd ordering and with the host network configuration this
  rover needs
- Heavier for a single-purpose appliance

### Option C — Versioned release tarball with symlink switch *(chosen)*

**Pros**
- Reproducible: tested bits, not a rebuild
- Fast install, no compiler on the production machine
- Rollback is a symlink switch and a service restart — seconds, and doable by phone
- Multiple releases coexist, so recovery does not need network access
- `dyx-version` can state exactly what is running

**Cons**
- Requires arm64 CI build infrastructure
- Artifact storage and retention to manage
- Config-schema migration between releases is on us
- Development still needs a source path, so there are two workflows

## Why we chose what we chose

Rollback decides it. Options A and B both work until a bad release reaches a rover in
the field; then A means a slow rebuild on site and B means a container runtime problem
on top of a software problem. The symlink switch is the only one recoverable by an
operator with no laptop.

## Consequences

**We accept:** arm64 CI infrastructure, artifact storage, and two workflows.

**We must therefore:**
- Keep configuration outside the release. `/etc/dyx/` survives upgrade and rollback, or
  rollback restores broken config alongside working code
- Make the installer idempotent (Section 46) and fail loudly. An installer that reports
  success while a service is dead is worse than one that crashes
- Version the config schema so an old release does not silently misread new config
- Define retention — how many releases stay on a disk that also holds bags

**Revisit if:** dependency isolation problems appear that only containers solve.
