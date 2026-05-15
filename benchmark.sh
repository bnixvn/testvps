#!/bin/bash
# Colors
GREEN="\033[0;32m"
PINK="\033[0;35m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# ==========================================
# CẤU HÌNH KIỂM TRA PORT
# ==========================================
CHECK_URL_8080="http://8080.legiang360.com:8080"

# Table width configuration
COL1_WIDTH=27
COL2_WIDTH=73
TABLE_WIDTH=107

print_line() {
  printf "+%*s+\n" $((TABLE_WIDTH - 2)) "" | tr ' ' '-'
}

print_kv_row() {
  local key="$1"
  local value="$2"
  printf "| ${CYAN}%-*s${RESET} | %-*b |\n" $((COL1_WIDTH)) "$key" $((COL2_WIDTH)) "$value"
  print_line
}

print_center_box() {
  local text="$1"
  printf "${GREEN}%s${RESET}\n\n" "$text"
}

print_section_header() {
  echo
  print_center_box "$1"
}

# --- SILENT INSTALL HELPER ---
silent_install() {
    local pkg_manager=$1
    shift
    local packages=("$@")
    echo -ne "  -> Installing dependencies (${packages[*]}) ... "
    
    if [ "$pkg_manager" == "apt" ]; then
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "yum" ]; then
        sudo yum install -y epel-release >/dev/null 2>&1
        sudo yum install -y "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "dnf" ]; then
        sudo dnf install -y "${packages[@]}" >/dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OK${RESET}"
    else
        echo -e "${RED}FAILED${RESET}"
        exit 1
    fi
}

# Check required tools (Silent)
check_dependencies() {
  local deps=("bc" "fio" "ioping" "jq" "wget" "curl")
  local missing=()
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing+=("$dep")
    fi
  done

  if [ ${#missing[@]} -ne 0 ]; then
    echo "Detected missing tools. Installing silently..."
    if command -v apt >/dev/null; then
      silent_install "apt" "${missing[@]}"
    elif command -v dnf >/dev/null; then
      silent_install "dnf" "${missing[@]}"
    elif command -v yum >/dev/null; then
      silent_install "yum" "${missing[@]}"
    else
      echo "Package manager not found. Please install manually: ${missing[*]}"
      exit 1
    fi
  fi
}

# System information functions
get_system_info() {
  if [ -f /etc/os-release ]; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  else
    OS_NAME=$(uname -srv)
  fi
  CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//' | head -1)
  CPU_CORES=$(nproc)
  CPU_MHZ=$(lscpu | awk '/MHz/ {print $3; exit}')
  CPU_IDLE=$(top -bn2 | grep "Cpu(s)" | tail -1 | awk -F',' '{print $4}' | awk '{print $1}')
  CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")
  RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
  RAM_USED=$(free -h | awk '/Mem:/ {print $3}')
  RAM_FREE=$(free -h | awk '/Mem:/ {print $4}')
  RAM_USAGE_PCT=$(free | awk '/Mem:/ {printf \"%.0f%%\", $3/$2 * 100}')
  SWAP_TOTAL=$(free -h | awk '/Swap:/ {print $2}')
  SWAP_USED=$(free -h | awk '/Swap:/ {print $3}')
  DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
  DISK_USED=$(df -h / | awk 'NR==2{print $3}')
  DISK_FREE=$(df -h / | awk 'NR==2{print $4}')
  DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')
  ARCH=$(uname -m)
  KERNEL=$(uname -r)
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt)
    [ "$VIRT" = "none" ] && VIRT="Physical"
  else
    VIRT="Unknown"
  fi
  UPTIME_SEC=$(cut -d. -f1 /proc/uptime)
  UPTIME_DAYS=$(( UPTIME_SEC / 86400 ))
  UPTIME_H=$(( (UPTIME_SEC % 86400) / 3600 ))
  UPTIME_M=$(( (UPTIME_SEC % 3600) / 60 ))
  if [ $UPTIME_DAYS -gt 0 ]; then
    UPTIME_STR="${UPTIME_DAYS} days, ${UPTIME_H}h ${UPTIME_M}m"
  else
    UPTIME_STR="${UPTIME_H}h ${UPTIME_M}m"
  fi
  LOADAVG=$(cut -d' ' -f1-3 /proc/loadavg)
}

display_system_info() {
  print_section_header "[ System Information ]"
  print_line
  print_kv_row "Operating System" "$OS_NAME"
  print_kv_row "Architecture" "$ARCH"
  print_kv_row "Kernel Version" "$KERNEL"
  print_kv_row "Virtualization" "$VIRT"
  print_kv_row "Processor" "$CPU_MODEL"
  print_kv_row "CPU Cores" "${CPU_CORES} Core(s) @ ${CPU_MHZ} MHz"
  print_kv_row "CPU Usage" "$CPU_USAGE"
  print_kv_row "System Uptime" "$UPTIME_STR"
  print_kv_row "Load Average" "$LOADAVG"
  print_kv_row "Memory" "${RAM_TOTAL} Total (Used: ${RAM_USED} - Free: ${RAM_FREE} - Usage: ${RAM_USAGE_PCT})"
  print_kv_row "Swap" "${SWAP_TOTAL} Total (Used: ${SWAP_USED})"
  print_kv_row "Disk (Root)" "${DISK_TOTAL} Total (Used: ${DISK_USED} - Free: ${DISK_FREE} - Usage: ${DISK_USAGE})"
}

# DD test functions
run_dd_test() {
  local LOCAL_TABLE_WIDTH=29
  print_section_header "[ DD Sequential Write Test ]"
  print_line_with_length $LOCAL_TABLE_WIDTH
  DD_SPEEDS=()
  printf "| %-7s | %-15s |\n" "Round" "Speed"
  print_line_with_length $LOCAL_TABLE_WIDTH
  for i in 1 2 3; do
    OUT=$(dd if=/dev/zero of=testfile_$i bs=4M count=256 oflag=direct 2>&1)
    speed=$(echo "$OUT" | grep -oE '[0-9]+(\.[0-9]+)?\s*[GMK]?B/s' | head -1)
    speed_num=$(echo "$speed" | grep -oE '[0-9]+(\.[0-9]+)?')
    speed_unit=$(echo "$speed" | grep -oE '[GMK]?B/s')
    case "$speed_unit" in
      GB/s) speed_mb=$(echo "$speed_num * 1024" | bc -l) ;;
      MB/s) speed_mb=$speed_num ;;
      KB/s) speed_mb=$(echo "$speed_num / 1024" | bc -l) ;;
      *) speed_mb=0 ;;
    esac
    DD_SPEEDS+=("$speed_mb")
    printf "| %-7s | ${YELLOW}%-15s${RESET} |\n" "Round $i" "$speed"
  done
  rm -f testfile_1 testfile_2 testfile_3
  sum=0
  count=0
  for v in "${DD_SPEEDS[@]}"; do
    if [ -n "$v" ] && (( $(echo "$v > 0" | bc -l) )); then
      sum=$(echo "$sum + $v" | bc -l)
      count=$((count + 1))
    fi
  done
  if (( count > 0 )); then
    avg=$(echo "scale=2; $sum / $count" | bc -l)
    if (( $(echo "$avg > 1024" | bc -l) )); then
      avg_display=$(echo "scale=2; $avg / 1024" | bc -l)
      avg_txt="${avg_display} GB/s"
    else
      avg_txt="${avg} MB/s"
    fi
  else
    avg_txt="N/A"
  fi
  print_line_with_length $LOCAL_TABLE_WIDTH
  printf "| %-7s | ${YELLOW}%-15s${RESET} |\n" "Average" "$avg_txt"
  print_line_with_length $LOCAL_TABLE_WIDTH
}

print_line_with_length() {
  local len=$1
  printf "+%*s+\n" "$((len - 2))" "" | tr ' ' '-'
}

# FIO test functions
run_fio_test() {
  local LOCAL_TABLE_WIDTH=102
  print_section_header "[ FIO Random Read/Write Test ]"
  print_line_with_length $LOCAL_TABLE_WIDTH
  CPU_CORES=$(nproc)
  NUMJOBS=$(( CPU_CORES > 8 ? 8 : CPU_CORES ))
  IODEPTH=$(( NUMJOBS * 2 ))
  (( IODEPTH > 16 )) && IODEPTH=16
  BLOCK_SIZES=("4k" "16k" "64k" "256k" "1M")
  printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
         "Block Size" "Total Throughput" "Read Speed" "Write Speed" "Total IOPS" "Read IOPS" "Write IOPS"
  print_line_with_length $LOCAL_TABLE_WIDTH
  for BS in "${BLOCK_SIZES[@]}"; do
    fio --name=fio_test --ioengine=libaio --rw=randrw --bs=$BS --direct=1 \
        --size=512M --numjobs=$NUMJOBS --iodepth=$IODEPTH --runtime=15 \
        --time_based --group_reporting=1 --output-format=json > fio_tmp.json 2>&1
    if [ ! -s fio_tmp.json ] || ! jq -e . > /dev/null 2>&1 < fio_tmp.json; then
      printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
             "$BS" "Test failed" "-" "-" "-" "-" "-"
      continue
    fi
    RD_BW=$(jq '[.jobs[].read.bw] | add' fio_tmp.json 2>/dev/null || echo "0")
    WR_BW=$(jq '[.jobs[].write.bw] | add' fio_tmp.json 2>/dev/null || echo "0")
    RD_IOPS=$(jq '[.jobs[].read.iops] | add' fio_tmp.json 2>/dev/null || echo "0")
    WR_IOPS=$(jq '[.jobs[].write.iops] | add' fio_tmp.json 2>/dev/null || echo "0")
    RD_MB=$(awk "BEGIN {printf \"%.0f\", $RD_BW / 1024}")
    WR_MB=$(awk "BEGIN {printf \"%.0f\", $WR_BW / 1024}")
    TOT_MB=$(( RD_MB + WR_MB ))
    if (( TOT_MB > 1024 )); then
      TOT_DISPLAY=$(awk "BEGIN {printf \"%.2f GB/s\", $TOT_MB/1024}")
    else
      TOT_DISPLAY="${TOT_MB} MB/s"
    fi
    if (( RD_MB > 1024 )); then
      RD_DISPLAY=$(awk "BEGIN {printf \"%.2f GB/s\", $RD_MB/1024}")
    else
      RD_DISPLAY="${RD_MB} MB/s"
    fi
    if (( WR_MB > 1024 )); then
      WR_DISPLAY=$(awk "BEGIN {printf \"%.2f GB/s\", $WR_MB/1024}")
    else
      WR_DISPLAY="${WR_MB} MB/s"
    fi
    IOPS_TOTAL=$(awk "BEGIN {printf \"%d\", ($RD_IOPS + $WR_IOPS)}")
    if (( IOPS_TOTAL >= 1000000 )); then
      IOPS_DISPLAY=$(awk "BEGIN {printf \"%.1fM\", $IOPS_TOTAL/1000000}")
    elif (( IOPS_TOTAL >= 1000 )); then
      IOPS_DISPLAY=$(awk "BEGIN {printf \"%.1fk\", $IOPS_TOTAL/1000}")
    else
      IOPS_DISPLAY=$IOPS_TOTAL
    fi
    RD_IOPS_INT=${RD_IOPS%.*}
    WR_IOPS_INT=${WR_IOPS%.*}
    printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
           "$BS" "$TOT_DISPLAY" "$RD_DISPLAY" "$WR_DISPLAY" "$IOPS_DISPLAY" "$RD_IOPS_INT" "$WR_IOPS_INT"
  done
  print_line_with_length $LOCAL_TABLE_WIDTH
  rm -f fio_tmp.json fio_test.* 2>/dev/null
}

# IOPing latency test
run_ioping_test() {
  local LOCAL_TABLE_WIDTH=45
  print_section_header "[ IOPing Latency Test ]"
  if ! command -v ioping >/dev/null 2>&1; then
    print_kv_row "Disk Latency" "${RED}ioping not available${RESET}"
    return
  fi
  LATENCY_RESULT=$(ioping -c 10 . 2>&1)
  local RET=$?
  if [ $RET -ne 0 ]; then
    print_kv_row "Disk Latency" "${RED}ioping test failed${RESET}"
    echo -e "${RED}ioping output:${RESET}\n$LATENCY_RESULT" >&2
    return
  fi
  local LATENCY_LINE=$(echo "$LATENCY_RESULT" | grep -E 'min/avg/max/mdev')
  if [ -z "$LATENCY_LINE" ]; then
    print_kv_row "Disk Latency" "${RED}Could not parse latency${RESET}"
    return
  fi
  local VALUES=$(echo "$LATENCY_LINE" | awk -F'= ' '{print $2}')
  IFS='/' read -r MIN_LAT AVG_LAT MAX_LAT MDEV_LAT <<< "$VALUES"
  MIN_LAT=$(echo "$MIN_LAT" | xargs)
  AVG_LAT=$(echo "$AVG_LAT" | xargs)
  MAX_LAT=$(echo "$MAX_LAT" | xargs)
  MDEV_LAT=$(echo "$MDEV_LAT" | xargs)
  print_line_with_length $LOCAL_TABLE_WIDTH
  printf "| %-18s | %-20s |\n" "Latency Type" "Value"
  print_line_with_length $LOCAL_TABLE_WIDTH
  printf "| %-18s | %-20b |\n" "Average Latency" "$AVG_LAT"
  printf "| %-18s | %-20s |\n" "Minimum Latency" "$MIN_LAT"
  printf "| %-18s | %-20s |\n" "Maximum Latency" "$MAX_LAT"
  print_line_with_length $LOCAL_TABLE_WIDTH
}

# --- SPEEDTEST CONFIGURATION & LOGIC ---

server_list=(
  17757
  17756
  17758
  9903
  10040
  26853
  2552
  44677
  2515
  44817
  19230
  8864
  50467
  1536
)

install_official_speedtest() {
    if command -v speedtest >/dev/null 2>&1; then
        if speedtest --version 2>&1 | grep -q "Ookla"; then
            return
        fi
    fi

    echo -ne "  -> Installing Official Ookla Speedtest (Silent Mode) ... "

    OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    fi

    case "$OS" in
