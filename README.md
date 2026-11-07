# Linux Server Health Check Toolkit

A lightweight Bash utility that collects basic Linux server health information and writes a plain-text report. This is a learning/demo project; review and test it in your environment before relying on it operationally.

## Features

- Hostname and uptime
- Root filesystem disk utilization
- Memory utilization based on `MemAvailable`
- 1-minute load average relative to CPU count
- Optional systemd service checks
- Configurable warning and critical thresholds
- Timestamped text report
- Basic smoke tests

## Requirements

- Linux and Bash
- Standard utilities: `awk`, `df`, `date`, `hostname`, `nproc`, `uptime`
- `systemctl` is optional for service checks

## Project layout

```text
linux-server-health-check/
├── health_check.sh
├── config/
│   └── thresholds.conf
├── reports/
├── tests/
│   └── test_health_check.sh
├── .gitignore
├── LICENSE
└── README.md
```

## Quick start

```bash
chmod +x health_check.sh
./health_check.sh
```

By default, reports are saved in `reports/`. Generated report files are ignored by Git.

## Configuration

Edit `config/thresholds.conf`:

```bash
DISK_WARN=80
DISK_CRIT=90
MEM_WARN=80
MEM_CRIT=90
LOAD_WARN_PER_CPU=1.0
LOAD_CRIT_PER_CPU=2.0
SERVICES_TO_CHECK=""
```

Load thresholds mean the 1-minute load average divided by CPU count. Optional services can be listed as space-separated systemd service names:

```bash
SERVICES_TO_CHECK="ssh cron"
```

Service names vary by Linux distribution (for example, `ssh` or `sshd`).

## Usage

```bash
./health_check.sh
./health_check.sh --config ./config/thresholds.conf
./health_check.sh --report ./reports/manual-report.txt
./health_check.sh --help
```

## Exit codes

- `0`: resource checks are OK
- `1`: at least one resource check is WARNING
- `2`: at least one resource check is CRITICAL, or config/usage validation failed

Service status is reported but does not currently affect the overall exit code.

## Tests

```bash
chmod +x tests/test_health_check.sh
./tests/test_health_check.sh
```

The tests are smoke tests for help output, report generation, and invalid configuration. Resource readings depend on the test host.

## Limitations

- Checks only the root (`/`) filesystem.
- Load average is a workload signal, not the same thing as CPU utilization.
- Does not yet check network, disk I/O, process-level usage, or container health.
- Service checks require systemd and valid service names.
- Thresholds should be tuned to the server and workload.

## Roadmap

- Add more threshold-comparison tests
- Add JSON output
- Support multiple filesystem paths
- Add ShellCheck linting with GitHub Actions
- Add an optional Docker-based test environment

## License

MIT. See [LICENSE](LICENSE).
