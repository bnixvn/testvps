#!/bin/bash
# Strict mode for better error handling
set -euo pipefail
IFS=$'\n\t'

# Temporary files tracking
tmp_files=()

# Cleanup function
cleanup() {
  for f in "${tmp_files[@]}"; do
    [ -f "$f" ] && rm -f "$f"
  done
}

# Register cleanup trap
trap cleanup EXIT

# SUDO helper - only use sudo when not running as root
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

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
  local width=$((TABLE_WIDTH - 2))
  if [ "$width" -le 0 ]; then width=1; fi
  printf "+%*s+\n" "$width" "" | tr ' ' '-'
}

print_kv_row() {
  local key="$1"
  local value="$2"
  printf "| ${CYAN}%-*s${RESET} | %-*s |\n" $((COL1_WIDTH)) "$key" $((COL2_WIDTH)) "$value"
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
        $SUDO apt-get update >/dev/null 2>&1
        $SUDO apt-get install -y "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "yum" ]; then
        $SUDO yum install -y epel-release >/dev/null 2>&1
        $SUDO yum install -y "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "dnf" ]; then
        $SUDO dnf install -y "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "apk" ]; then
        $SUDO apk add --no-cache "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "pacman" ]; then
        $SUDO pacman -Sy --noconfirm "${packages[@]}" >/dev/null 2>&1
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
    elif command -v apk >/dev/null; then
      silent_install "apk" "${missing[@]}"
    elif command -v pacman >/dev/null; then
      silent_install "pacman" "${missing[@]}"
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
  RAM_USAGE_PCT=$(free | awk '/Mem:/ {printf "%.0f%%", $3/$2 * 100}')
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
    # Create temp file for this round
    local testfile
    testfile=$(mktemp /tmp/dd_test_XXXXXX)
    tmp_files+=("$testfile")
    
    # Run dd with conv=fdatasync to ensure stats are printed, capture stderr
    OUT=$(dd if=/dev/zero of="$testfile" bs=4M count=256 oflag=direct conv=fdatasync 2>&1)
    
    # Parse speed from dd output (stderr)
    speed=$(echo "$OUT" | grep -oE '[0-9]+(\.[0-9]+)?\s*[GMK]?B/s' | tail -1)
    speed_num=$(echo "$speed" | grep -oE '[0-9]+(\.[0-9]+)?' || echo "0")
    speed_unit=$(echo "$speed" | grep -oE '[GMK]?B/s' || echo "B/s")
    
    case "$speed_unit" in
      GB/s) speed_mb=$(echo "$speed_num * 1024" | bc -l) ;;
      MB/s) speed_mb=$speed_num ;;
      KB/s) speed_mb=$(echo "$speed_num / 1024" | bc -l) ;;
      *) speed_mb=0 ;;
    esac
    DD_SPEEDS+=("$speed_mb")
    printf "| %-7s | ${YELLOW}%-15s${RESET} |\n" "Round $i" "$speed"
  done
  
  # Calculate average
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
  local width=$((len - 2))
  if [ "$width" -le 0 ]; then width=1; fi
  printf "+%*s+\n" "$width" "" | tr ' ' '-'
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
    # Create temp JSON file
    local fio_json
    fio_json=$(mktemp /tmp/fio_test_XXXXXX.json)
    tmp_files+=("$fio_json")
    
    fio --name=fio_test --ioengine=libaio --rw=randrw --bs=$BS --direct=1 \
        --size=512M --numjobs=$NUMJOBS --iodepth=$IODEPTH --runtime=15 \
        --time_based --group_reporting=1 --output="$fio_json" --output-format=json >/dev/null 2>&1
    
    # Validate JSON before parsing
    if [ ! -s "$fio_json" ] || ! jq -e . "$fio_json" >/dev/null 2>&1; then
      printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
             "$BS" "Test failed" "-" "-" "-" "-" "-"
      continue
    fi
    RD_BW=$(jq '[.jobs[].read.bw] | add' "$fio_json" 2>/dev/null || echo "0")
    WR_BW=$(jq '[.jobs[].write.bw] | add' "$fio_json" 2>/dev/null || echo "0")
    RD_IOPS=$(jq '[.jobs[].read.iops] | add' "$fio_json" 2>/dev/null || echo "0")
    WR_IOPS=$(jq '[.jobs[].write.iops] | add' "$fio_json" 2>/dev/null || echo "0")
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
  # Clean up any leftover fio test files
  rm -f fio_test.* 2>/dev/null || true
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
  
  # Try to parse latency from output
  local LATENCY_LINE=$(echo "$LATENCY_RESULT" | grep -E 'min/avg/max/mdev' || echo "")
  if [ -z "$LATENCY_LINE" ]; then
    # Fallback: couldn't parse, print raw output for debugging
    print_kv_row "Disk Latency" "${YELLOW}Could not parse (see below)${RESET}"
    echo -e "${YELLOW}ioping raw output:${RESET}\n$LATENCY_RESULT"
    return
  fi
  
  # Extract values after '= '
  local VALUES=$(echo "$LATENCY_LINE" | awk -F'= ' '{print $2}' || echo "")
  if [ -z "$VALUES" ]; then
    print_kv_row "Disk Latency" "${YELLOW}Could not parse latency${RESET}"
    echo -e "${YELLOW}ioping raw output:${RESET}\n$LATENCY_RESULT"
    return
  fi
  
  IFS='/' read -r MIN_LAT AVG_LAT MAX_LAT MDEV_LAT <<< "$VALUES"
  MIN_LAT=$(echo "$MIN_LAT" | xargs)
  AVG_LAT=$(echo "$AVG_LAT" | xargs)
  MAX_LAT=$(echo "$MAX_LAT" | xargs)
  MDEV_LAT=$(echo "$MDEV_LAT" | xargs)
  
  print_line_with_length $LOCAL_TABLE_WIDTH
  printf "| %-18s | %-20s |\n" "Latency Type" "Value"
  print_line_with_length $LOCAL_TABLE_WIDTH
  printf "| %-18s | %-20s |\n" "Average Latency" "$AVG_LAT"
  printf "| %-18s | %-20s |\n" "Minimum Latency" "$MIN_LAT"
  printf "| %-18s | %-20s |\n" "Maximum Latency" "$MAX_LAT"
  print_line_with_length $LOCAL_TABLE_WIDTH
}

# --- SPEEDTEST CONFIGURATION & LOGIC ---

# Danh sách server Speedtest ID
server_list=(
  17757 # VNPT NET Ha Noi
  17756 # VNPT NET Da Nang
  17758 # VNPT NET Ho Chi Minh
  9903  # Viettel Network Ha Noi
  10040 # Viettel Network Da Nang
  26853 # Viettel Network Ho Chi Minh
  2552  # FPT Telecom Ha Noi
  44677 # FPT Telecom Da Nang
  2515  # FPT Telecom Ho Chi Minh
  44817 # SPTEL PTE Ltd Singapore
  19230 # Hivelocity Los Angeles
  8864  # CenturyLink Seattle
  50467 # Verizon Tokyo Japan
  1536  # STC Hong Kong
)

install_official_speedtest() {
  # Check if official binary is already installed
  if command -v speedtest >/dev/null 2>&1; then
    if speedtest --version 2>&1 | grep -q "Ookla"; then
        return
    fi
  fi

  echo -ne "  -> Installing Official Ookla Speedtest Binary ... "
  
  # Detect OS details for installation method
  local OS_ID=""
  local OS_VER=""
  
  if [ -f /etc/os-release ]; then
      . /etc/os-release
      OS_ID=$ID
      OS_VER=$(echo "$VERSION_ID" | cut -d. -f1) # Major version
  fi

  # LOGIC: Ubuntu >= 25 uses SNAP
  if [[ "$OS_ID" == "ubuntu" ]] && [[ "$OS_VER" -ge 25 ]]; then
      echo -ne "(Snap) ... "
      if command -v snap >/dev/null 2>&1; then
          $SUDO snap install speedtest >/dev/null 2>&1
      else
          echo -e "${RED}Snap not found${RESET}"
          return 1
      fi
  
  # Standard Debian/Ubuntu < 25
  elif [ -f /etc/debian_version ]; then
      curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | $SUDO bash >/dev/null 2>&1
      $SUDO apt-get install -y speedtest >/dev/null 2>&1
      
  # RHEL/CentOS/Alma/Rocky
  elif [ -f /etc/redhat-release ]; then
      curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | $SUDO bash >/dev/null 2>&1
      $SUDO yum install -y speedtest >/dev/null 2>&1
  else
      echo -e "${RED}FAILED (Unsupported OS)${RESET}"
      return 1
  fi

  if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK${RESET}"
  else
      echo -e "${RED}FAILED${RESET}"
  fi
}

run_speedtest_official_binary() {
  local SERVER_ID=$1
  local JSON_OUTPUT=$(speedtest --accept-license --accept-gdpr --server-id "$SERVER_ID" -f json 2>/dev/null)
  
  # Validate JSON with jq -e before parsing
  if [ -z "$JSON_OUTPUT" ] || ! echo "$JSON_OUTPUT" | jq -e . >/dev/null 2>&1; then 
      return 1 
  fi
  
  # Also check for error type in JSON
  if [ "$(echo "$JSON_OUTPUT" | jq -r '.type' 2>/dev/null)" == "error" ]; then 
      return 1 
  fi

  local DL_BYTES=$(echo "$JSON_OUTPUT" | jq -r '.download.bandwidth')
  local UL_BYTES=$(echo "$JSON_OUTPUT" | jq -r '.upload.bandwidth')
  local LATENCY=$(echo "$JSON_OUTPUT" | jq -r '.ping.latency')
  local SERVER_NAME=$(echo "$JSON_OUTPUT" | jq -r '.server.name')
  local SERVER_LOC=$(echo "$JSON_OUTPUT" | jq -r '.server.location')
  
  local DL_MBPS=$(awk "BEGIN {printf \"%.2f\", $DL_BYTES * 8 / 1000000}")
  local UL_MBPS=$(awk "BEGIN {printf \"%.2f\", $UL_BYTES * 8 / 1000000}")
  local PING_MS=$(awk "BEGIN {printf \"%.2f\", $LATENCY}")

  echo "$SERVER_ID|$SERVER_NAME ($SERVER_LOC)|$DL_MBPS Mbps|$UL_MBPS Mbps|$PING_MS ms"
}

print_speedtest_header() {
  local WIDTH=95
  printf "+%*s+\n" $((WIDTH - 6)) "" | tr ' ' '-'
  printf "| %-6s | %-30s | %-15s | %-12s | %-12s |\n" "ID" "Server" "Download" "Upload" "Latency"
  printf "+%*s+\n" $((WIDTH - 6)) "" | tr ' ' '-'
}

print_speedtest_row() {
  local id="$1"
  local server="$2"
  local dl="$3"
  local ul="$4"
  local lat="$5"
  
  id=$(echo "$id" | tr -d '\r\n')
  server=$(echo "$server" | tr -d '\r\n')
  dl=$(echo "$dl" | tr -d '\r\n')
  ul=$(echo "$ul" | tr -d '\r\n')
  lat=$(echo "$lat" | tr -d '\r\n')

  if [ ${#server} -gt 30 ]; then server="${server:0:27}..."; fi
  printf "| %-6s | %-30s | %-15s | %-12s | %-12s |\n" "$id" "$server" "$dl" "$ul" "$lat"
}

# --- FALLBACK HTTP METHOD (CURL) ---

test_url_speed() {
    local url=$1
    local name=$2
    
    # Use curl with write-out to get speed_download in bytes/sec
    local speed_bytes
    speed_bytes=$(curl -f -s -o /dev/null -w "%{speed_download}" --max-time 10 "$url" 2>/dev/null || echo "0")
    
    local display_speed="Error"
    
    # Convert bytes/sec to Mbps
    if [ -n "$speed_bytes" ] && [ "$speed_bytes" != "0" ] && [ "$speed_bytes" != "0.000" ]; then
        # speed_download is in bytes/sec, convert to Mbps: bytes/sec * 8 / 1000000
        display_speed=$(echo "scale=2; $speed_bytes * 8 / 1000000" | bc)
        display_speed="${display_speed} Mbps"
    fi

    # LOGIC: Upload = Download in Fallback mode
    local upload_speed="$display_speed"

    # Compute ping safely
    local domain
    domain=$(echo "$url" | awk -F'/' '{print $3}')
    local ping
    ping=$(ping -c1 -W 2 "$domain" 2>/dev/null | awk -F'time=' '{print $2}' | cut -d ' ' -f 1 | tr -d '\r\n' || echo "")
    
    if [ -z "$ping" ]; then 
        ping="-"
    else 
        ping="${ping} ms"
    fi
    
    print_speedtest_row "HTTP" "$name" "$display_speed" "$upload_speed" "$ping"
}

run_fallback_speedtest() {
    echo -e "${RED}Cannot connect speedtest because port 8080 is close${RESET}"
    echo -e "${YELLOW}Switching to HTTP Download method (Fallback Mode).${RESET}"
    print_speedtest_header
    
    # International
    test_url_speed 'https://wa-us-ping.vultr.com/vultr.com.100MB.bin' 'Vultr Seattle, US'
    test_url_speed 'http://tyo.download.datapacket.com/100mb.bin' 'CDN77, JP'
    test_url_speed 'http://speedtest.c1.hkg1.dediserve.com/100MB.test' 'Dediserve Hong Kong, HK'
    test_url_speed 'https://sgp.proof.ovh.net/files/100Mb.dat' 'OVH Singapore, SG'
    test_url_speed 'https://speed.cloudflare.com/__down?during=download&bytes=104857600' 'Cloudflare Anycast'
    
    # Vietnam
    test_url_speed 'http://speedtest1.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT Ha Noi, VN'
    test_url_speed 'http://speedtest5.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT Da Nang, VN'
    test_url_speed 'http://speedtest3.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT Ho Chi Minh, VN'
    test_url_speed 'http://speedtestkv1a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Ha Noi, VN'
    test_url_speed 'http://speedtestkv2a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Da Nang, VN'
    test_url_speed 'http://centos-hcm.viettelidc.com.vn/7/isos/x86_64/CentOS-7-x86_64-Minimal-2207-02.iso' 'Viettel Ho Chi Minh, VN'
    #test_url_speed 'http://speedtesthn.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Ha Noi, VN'
    #test_url_speed 'http://speedtest.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Ho Chi Minh, VN'
    
    local WIDTH=95
    printf "+%*s+\n" $((WIDTH - 6)) "" | tr ' ' '-'
}

# --- SMART SPEEDTEST RUNNER ---

check_outbound_port_8080() {
    local url="$CHECK_URL_8080"
    echo -ne "Checking outbound 8080 ... "
    if curl -f -s -I --connect-timeout 5 "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${RESET}"
        return 0
    else
        echo -e "${RED}Failed${RESET}"
        return 1
    fi
}

run_speedtest_all_official() {
  print_section_header "[ Network Speed Test (Official Ookla Binary) ]"
  install_official_speedtest

  # Check Port
  if check_outbound_port_8080; then
      echo -e "${GREEN}Port 8080 is open. Using Official Speedtest Binary.${RESET}"
      print_speedtest_header
      
      for SERVER_ID in "${server_list[@]}"; do
        local result
        result=$(run_speedtest_official_binary "$SERVER_ID") || true
        if [ -n "$result" ]; then
          IFS='|' read -r id server dl ul lat <<< "$result"
          print_speedtest_row "$id" "$server" "$dl" "$ul" "$lat"
        else
          printf "| %-6s | %-30s | %-15s | %-12s | %-12s |\n" "$SERVER_ID" "Test Failed" "-" "-" "-"
        fi
      done
      local WIDTH=95
      printf "+%*s+\n" $((WIDTH - 6)) "" | tr ' ' '-'
      
  else
      run_fallback_speedtest
  fi
}

# Main execution
main() {
  clear
  echo -e "${CYAN}System Benchmark Tool${RESET}"
  echo -e "${YELLOW}Starting comprehensive system tests...${RESET}\n"
  check_dependencies
  get_system_info
  display_system_info
  
  run_dd_test
  run_fio_test
  run_ioping_test
  
  # Network test
  run_speedtest_all_official
  
  echo -e "\n${GREEN}All tests completed successfully!${RESET}"
}

main "$@"
