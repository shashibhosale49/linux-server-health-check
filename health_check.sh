#!/usr/bin/env bash
# Linux Server Health Check Toolkit
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/config/thresholds.conf}"
REPORT_FILE="${REPORT_FILE:-${SCRIPT_DIR}/reports/health-report-$(date +%Y%m%d-%H%M%S).txt}"

DISK_WARN=80
DISK_CRIT=90
MEM_WARN=80
MEM_CRIT=90
LOAD_WARN_PER_CPU=1.0
LOAD_CRIT_PER_CPU=2.0
SERVICES_TO_CHECK=""

usage() {
  cat <<'EOF'
Usage: ./health_check.sh [options]
  --config PATH   Configuration file
  --report PATH   Report output path
  --help          Show help
EOF
}

log() { printf '%s\n' "$*" | tee -a "$REPORT_FILE"; }

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      value="${value%\"}"
      value="${value#\"}"
      case "$key" in
        DISK_WARN|DISK_CRIT|MEM_WARN|MEM_CRIT|LOAD_WARN_PER_CPU|LOAD_CRIT_PER_CPU|SERVICES_TO_CHECK)
          printf -v "$key" '%s' "$value" ;;
        *) printf 'Ignoring unsupported config key: %s\n' "$key" >&2 ;;
      esac
    else
      printf 'Ignoring malformed config line.\n' >&2
    fi
  done < "$CONFIG_FILE"
}

get_disk_usage() {
  df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
}

get_memory_usage() {
  awk '
    /^MemTotal:/ { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END {
      if (total > 0) printf "%.0f\n", ((total-available)/total)*100
      else print "0"
    }
  ' /proc/meminfo
}

status_for() {
  awk -v value="$1" -v warn="$2" -v crit="$3" 'BEGIN {
    if (value >= crit) print "CRITICAL"
    else if (value >= warn) print "WARNING"
    else print "OK"
  }'
}

validate_thresholds() {
  local key value
  for key in DISK_WARN DISK_CRIT MEM_WARN MEM_CRIT LOAD_WARN_PER_CPU LOAD_CRIT_PER_CPU; do
    value="${!key}"
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
      printf 'Invalid numeric value for %s: %s\n' "$key" "$value" >&2
      return 1
    }
  done
  (( DISK_WARN <= DISK_CRIT && MEM_WARN <= MEM_CRIT )) || {
    echo "Warning thresholds must not exceed critical thresholds." >&2
    return 1
  }
}

check_service() {
  local service="$1" state
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$service"; then state="ACTIVE"; else state="INACTIVE"; fi
  else
    state="SYSTEMCTL_UNAVAILABLE"
  fi
  printf 'Service %-24s %s' "$service" "$state"
}

main() {
  while (($#)); do
    case "$1" in
      --config) [[ $# -ge 2 ]] || { echo "--config requires a path" >&2; return 2; }; CONFIG_FILE="$2"; shift 2 ;;
      --report) [[ $# -ge 2 ]] || { echo "--report requires a path" >&2; return 2; }; REPORT_FILE="$2"; shift 2 ;;
      --help|-h) usage; return 0 ;;
      *) printf 'Unknown option: %s\n' "$1" >&2; usage; return 2 ;;
    esac
  done

  load_config
  validate_thresholds || return 2
  mkdir -p "$(dirname -- "$REPORT_FILE")" || return 1
  : > "$REPORT_FILE" || { echo "Cannot write report: $REPORT_FILE" >&2; return 1; }

  local host up disk mem cpus load disk_status mem_status load_status overall="OK" service status
  host="$(hostname 2>/dev/null || echo unknown)"
  up="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
  disk="$(get_disk_usage)"
  mem="$(get_memory_usage)"
  cpus="$(nproc 2>/dev/null || echo 1)"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"

  disk_status="$(status_for "$disk" "$DISK_WARN" "$DISK_CRIT")"
  mem_status="$(status_for "$mem" "$MEM_WARN" "$MEM_CRIT")"
  load_status="$(awk -v load="$load" -v cpus="$cpus" -v warn="$LOAD_WARN_PER_CPU" -v crit="$LOAD_CRIT_PER_CPU" 'BEGIN {
    if (cpus <= 0) cpus=1
    ratio=load/cpus
    if (ratio >= crit) print "CRITICAL"
    else if (ratio >= warn) print "WARNING"
    else print "OK"
  }')"

  log "===== Linux Server Health Report ====="
  log "Timestamp: $(date --iso-8601=seconds 2>/dev/null || date)"
  log "Hostname: $host"
  log "Uptime: $up"
  log ""
  log "===== Resource Checks ====="
  log "Disk usage (/): ${disk}% - ${disk_status} (warn ${DISK_WARN}%, crit ${DISK_CRIT}%)"
  log "Memory usage: ${mem}% - ${mem_status} (warn ${MEM_WARN}%, crit ${MEM_CRIT}%)"
  log "CPU load (1m): ${load}; CPUs: ${cpus}; load/CPU status: ${load_status}"
  log ""

  for service in $SERVICES_TO_CHECK; do log "$(check_service "$service")"; done

  for status in "$disk_status" "$mem_status" "$load_status"; do
    if [[ "$status" == "CRITICAL" ]]; then overall="CRITICAL"
    elif [[ "$status" == "WARNING" && "$overall" == "OK" ]]; then overall="WARNING"
    fi
  done

  log ""
  log "Overall status: $overall"
  log "Report saved to: $REPORT_FILE"
  case "$overall" in CRITICAL) return 2 ;; WARNING) return 1 ;; *) return 0 ;; esac
}
main "$@"
