# CardioVolt

CardioVolt is a lightweight, high-performance command-line utility written in V for hardware security audits, side-channel power profiling, and hardware backdoor detection. By establishing dynamic, multi-state baseline profiles of system power management integrated circuits (PMICs) and regulator rails, CardioVolt monitors electrical vital signs to assist in identifying anomalies that may indicate active hardware implants or unauthorized physical modifications.

## Features

- **Continuous Multi-State Profiling**: Collects voltage samples over a configurable duration during the baseline generation phase rather than taking a single, static snapshot.
- **Discrete State Clustering**: Automatically groups distinct stable voltage ranges (e.g., low-power idle states vs. high-performance CPU core spikes) to accommodate dynamic voltage frequency scaling (DVFS) and minimize false positives.
- **Auto-Calibrated Per-Sensor Margins**: Dynamically establishes independent tolerance boundaries for each regulator based on the variance observed during its specific training phase.
- **Generic Linux Kernel Interface**: Operates across diverse architectures (Android devices, single-board computers, laptops, and servers) by reading raw sysfs entries via `/sys/class/regulator` and `/sys/class/power_supply`.
- **Zero Runtime Dependencies**: Compiles directly into a single, high-performance static binary with zero external runtime requirements or heavy daemon installations.

---

## Quick Start (One-Liner)
```bash
pkg update -y && pkg install -y git clang make && if ! command -v v >/dev/null 2>&1; then git clone --depth=1 https://github.com/vlang/v && cd v && make && ./v symlink && cd ..; fi && git clone --depth=1 https://github.com/tailsmails/cardiovolt && cd cardiovolt && v -prod cardiovolt.v -o cardiovolt && ln -sf $(pwd)/cardiovolt $PREFIX/bin/cardiovolt
```

---

## Usage

*Note: Accessing raw sysfs voltage interfaces generally requires root privileges (`sudo` or a rooted shell).*

### 1. Generating a Normal Baseline (Training Mode)
To profile the system's power rails during standard operation, run the `save` command. It is recommended to perform this while simulated or typical workloads are active so the state-clustering engine can register normal power transitions.

```bash
# Samples rails for 30 seconds, polling every 250ms, with a 3.5% margin
sudo ./cardiovolt -d 30 -i 250 -m 3.5 save
```
*Creates `voltage_baseline.json` detailing the safe multi-state boundaries for each detected hardware sensor.*

### 2. Performing a Security Audit (Verification Mode)
Compare current system voltages against the saved baseline to check for abnormal power consumption or unexpected rail states.

```bash
sudo ./cardiovolt check
```

### 3. Detailed Verbose Audit
If you want to view a full diagnostic printout of all monitored sensors (including those within normal parameters) instead of just anomalies:

```bash
sudo ./cardiovolt -m 2.0 -v check
```

### 4. Auditing Custom Hardware Paths
For custom embedded systems, Android devices, or specific kernel versions that utilize non-standard sysfs paths, you can adjust the search patterns:

```bash
sudo ./cardiovolt -r "/sys/devices/platform/*.pmic/microvolts" save
```

---

## Technical Specifications / Flags

| Flag | Long Flag | Default | Purpose |
| :--- | :--- | :--- | :--- |
| `-d` | `--duration` | `10` | Sampling duration in seconds for baseline generation |
| `-i` | `--interval` | `500` | Sampling interval in milliseconds between polls |
| `-m` | `--margin` | `5.0` | Tolerance margin percentage allowed around baseline ranges |
| `-f` | `--file` | `voltage_baseline.json` | Path to read/write the baseline JSON database |
| `-v` | `--verbose` | `false` | Prints all checked sensor values and status, not just anomalies |
| `-r` | `--regulator` | `/sys/class/regulator/regulator.*/microvolts` | Glob search pattern for PMIC regulators |
| `-p` | `--power` | `/sys/class/power_supply/*/voltage_now` | Glob search pattern for power supplies/batteries |

---

## Why CardioVolt?
Standard software-level Intrusion Detection Systems (IDS) inspect memory spaces, processes, network packets, or system logs. However, they are blind to physical modifications—such as interposer chips, spy transceivers, or hardware keyloggers soldered directly onto power lines. 

Because any active physical implant must draw current to operate, it introduces a load that subtly affects the target voltage rail. **CardioVolt** acts like a stethoscope for your hardware. By mapping out the "resting heart rate" and dynamic workload spikes of your system, it seeks to flag the electrical "arrhythmias" caused by malicious physical additions trying to operate silently in the background.

## License
![License](https://img.shields.io/badge/License-MIT-green.svg)
