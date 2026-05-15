#!/bin/bash
# Full benchmark script (complete, self-contained)
# - Installs dependencies first (silent)
# - Runs all tests (system info, dd, fio, ioping, speedtest/fallback)
# - Logs current run to benchmark_result.txt (tee so output still shows on SSH)
# - Uploads the log to public web paste services and prints the result URL
#
# Usage:
#   chmod +x benchmark_full.sh
#   ./benchmark_full.sh

# -------------------------
# Colors
# -------------------------
GREEN="\033[0;32m"
PINK="\033[0;35m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# ==========================================
# CONFIG
# ==========================================
CHECK_URL_8080="http://8080.legiang360.com:8080"
LOG_FILE="benchmark_result.txt"
# Optional: set CUSTOM_UPLOAD_URL to your own endpoint that accepts multipart field "file".
# Example: CUSTOM_UPLOAD_URL="https://benchmark.bnix.io.vn/upload.php" ./benchmark.sh
CUSTOM_UPLOAD_URL="${CUSTOM_UPLOAD_URL:-https://benchmark.bnix.io.vn/upload.php}"

# Flag to avoid reinstalling speedtest multiple times
SPEEDTEST_INSTALLED=0

# Table width configuration
COL1_WIDTH=27
COL2_WIDTH=73
TABLE_WIDTH=107

# -------------------------
# Utility printing functions
# -------------------------
print_line() {
  printf "+%*s+\n" $((TABLE_WIDTH - 2)) "" | tr ' ' '-'
}

print_line_with_length() {
  local len=$1
  printf "+%*s+\n" "$((len - 2))" "" | tr ' ' '-'
}

print_kv_row() {
  local key="$1"
  local value="$2"
  # Use %b to allow color sequences in value
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

# -------------------------
# Silent install helpers
# -------------------------
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
    elif [ "$pkg_manager" == "apk" ]; then
        sudo apk add --no-cache "${packages[@]}" >/dev/null 2>&1
    elif [ "$pkg_manager" == "pacman" ]; then
        sudo pacman -Sy --noconfirm "${packages[@]}" >/dev/null 2>&1
    else
        echo -e "${RED}Unknown package manager${RESET}"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OK${RESET}"
    else
        echo -e "${RED}FAILED${RESET}"
        return 1
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
      silent_install "apt" "${missing[@]}" || exit 1
    elif command -v dnf >/dev/null; then
      silent_install "dnf" "${missing[@]}" || exit 1
    elif command -v yum >/dev/null; then
      silent_install "yum" "${missing[@]}" || exit 1
    elif command -v apk >/dev/null; then
      silent_install "apk" "${missing[@]}" || exit 1
    elif command -v pacman >/dev/null; then
      silent_install "pacman" "${missing[@]}" || exit 1
    else
      echo "Package manager not found. Please install manually: ${missing[*]}"
      exit 1
    fi
  else
    echo "All required tools present."
  fi
}

# -------------------------
# Speedtest installation (official Ookla binary)
# -------------------------
install_official_speedtest() {
    # If speedtest exists and is Ookla, skip
    if command -v speedtest >/dev/null 2>&1; then
        if speedtest --version 2>&1 | grep -q "Ookla"; then
            SPEEDTEST_INSTALLED=1
            return 0
        fi
    fi

    OS=""
    VER=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi

    case "$OS" in
        ubuntu|debian)
            if [[ "$VER" == "24.04" ]]; then
                wget -qO - https://raw.githubusercontent.com/VadimBoev/speedtest-cli-ubuntu-24.04-LTS/main/install.sh \
              | sudo bash >/dev/null 2>&1 || return 1
            else
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh \
                    | sudo bash >/dev/null 2>&1
            sudo apt-get install -y speedtest >/dev/null 2>&1 || return 1
            fi
            ;;
        rhel|centos|rocky|almalinux|fedora)
            curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh \
                | sudo bash >/dev/null 2>&1
            sudo yum install -y speedtest >/dev/null 2>&1 || sudo dnf install -y speedtest >/dev/null 2>&1
            ;;
        arch)
            sudo pacman -Sy --noconfirm speedtest-cli >/dev/null 2>&1
            ;;
        alpine)
            sudo apk add speedtest-cli >/dev/null 2>&1
            ;;
        macos|darwin)
            if command -v brew >/dev/null 2>&1; then
                brew install speedtest-cli >/dev/null 2>&1
            else
                return 1
            fi
            ;;
        freebsd)
            sudo pkg install -y speedtest >/dev/null 2>&1
            ;;
        *)
            if command -v snap >/dev/null 2>&1; then
                sudo snap install speedtest >/dev/null 2>&1
            else
                return 1
            fi
            ;;
    esac

    # Refresh shell hash so newly installed binary is found
    hash -r 2>/dev/null || true

    if command -v speedtest >/dev/null 2>&1; then
        SPEEDTEST_INSTALLED=1
        return 0
    else
        return 1
    fi
}

# -------------------------
# install_all: run all installs first
# -------------------------
install_all() {
    echo -e "${YELLOW}Installing all required components...${RESET}"
    check_dependencies
    install_official_speedtest
    echo -e "${GREEN}All installations completed!${RESET}"
}

# -------------------------
# System info functions
# -------------------------
get_system_info() {
  if [ -f /etc/os-release ]; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  else
    OS_NAME=$(uname -srv)
  fi
  CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//' | head -1 2>/dev/null || echo "Unknown")
  CPU_CORES=$(nproc 2>/dev/null || echo "1")
  CPU_MHZ=$(lscpu | awk '/MHz/ {print $3; exit}' 2>/dev/null || echo "-")
  CPU_IDLE=$(top -bn2 | grep "Cpu(s)" | tail -1 | awk -F',' '{print $4}' | awk '{print $1}' 2>/dev/null || echo "0")
  CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}" 2>/dev/null || echo "N/A")
  RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}' 2>/dev/null || echo "N/A")
  RAM_USED=$(free -h | awk '/Mem:/ {print $3}' 2>/dev/null || echo "N/A")
  RAM_FREE=$(free -h | awk '/Mem:/ {print $4}' 2>/dev/null || echo "N/A")
  RAM_USAGE_PCT=$(free | awk '/Mem:/ {printf \"%.0f%%\", $3/$2 * 100}' 2>/dev/null || echo "N/A")
  SWAP_TOTAL=$(free -h | awk '/Swap:/ {print $2}' 2>/dev/null || echo "N/A")
  SWAP_USED=$(free -h | awk '/Swap:/ {print $3}' 2>/dev/null || echo "N/A")
  DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}' 2>/dev/null || echo "N/A")
  DISK_USED=$(df -h / | awk 'NR==2{print $3}' 2>/dev/null || echo "N/A")
  DISK_FREE=$(df -h / | awk 'NR==2{print $4}' 2>/dev/null || echo "N/A")
  DISK_USAGE=$(df -h / | awk 'NR==2{print $5}' 2>/dev/null || echo "N/A")
  ARCH=$(uname -m 2>/dev/null || echo "N/A")
  KERNEL=$(uname -r 2>/dev/null || echo "N/A")
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt)
    [ "$VIRT" = "none" ] && VIRT="Physical"
  else
    VIRT="Unknown"
  fi
  if [ -r /proc/uptime ]; then
    UPTIME_SEC=$(cut -d. -f1 /proc/uptime)
    UPTIME_DAYS=$(( UPTIME_SEC / 86400 ))
    UPTIME_H=$(( (UPTIME_SEC % 86400) / 3600 ))
    UPTIME_M=$(( (UPTIME_SEC % 3600) / 60 ))
    if [ $UPTIME_DAYS -gt 0 ]; then
      UPTIME_STR="${UPTIME_DAYS} days, ${UPTIME_H}h ${UPTIME_M}m"
    else
      UPTIME_STR="${UPTIME_H}h ${UPTIME_M}m"
    fi
  else
    UPTIME_STR="N/A"
  fi
  LOADAVG=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "N/A")
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

# -------------------------
# DD test functions
# -------------------------
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
    speed_num=$(echo "$speed" | grep -oE '[0-9]+(\.[0-9]+)?' || echo "")
    speed_unit=$(echo "$speed" | grep -oE '[GMK]?B/s' || echo "")
    case "$speed_unit" in
      GB/s) speed_mb=$(echo "$speed_num * 1024" | bc -l) ;;
      MB/s) speed_mb=$speed_num ;;
      KB/s) speed_mb=$(echo "$speed_num / 1024" | bc -l) ;;
      *) speed_mb=0 ;;
    esac
    DD_SPEEDS+=("$speed_mb")
    printf "| %-7s | ${YELLOW}%-15s${RESET} |\n" "Round $i" "${speed:-N/A}"
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

# -------------------------
# FIO test functions
# -------------------------
run_fio_test() {
  local LOCAL_TABLE_WIDTH=102
  print_section_header "[ FIO Random Read/Write Test ]"
  print_line_with_length $LOCAL_TABLE_WIDTH
  CPU_CORES=$(nproc 2>/dev/null || echo 1)
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

# -------------------------
# IOPing latency test
# -------------------------
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

# -------------------------
# SPEEDTEST configuration & logic
# -------------------------
server_list=(
  17757 # VNPT NET Ha Noi
  17756 # VNPT NET Da Nang
  17758 # VNPT NET Ho Chi Minh
  9903  # Viettel Network Ha Noi
  10040 # Viettel Network Da Nang
  26853 # Viettel Network Ho Chi Minh
  2552  # FPT Telecom Ha Noi
  44677 # FPT Telecom Da Nang
  11342 # VIETPN CO, LTD
  44817 # SPTEL PTE Ltd Singapore
  19230 # Hivelocity Los Angeles
  8864  # CenturyLink Seattle
  50467 # Verizon Tokyo Japan
  1536  # STC Hong Kong
)

run_speedtest_official_binary() {
  local SERVER_ID=$1
  local JSON_OUTPUT
  JSON_OUTPUT=$(speedtest --accept-license --accept-gdpr --server-id "$SERVER_ID" -f json 2>/dev/null) || return 1
  
  if [ -z "$JSON_OUTPUT" ] || [ "$(echo "$JSON_OUTPUT" | jq -r '.type' 2>/dev/null)" == "error" ]; then 
      return 1 
  fi

  local DL_BYTES UL_BYTES LATENCY SERVER_NAME SERVER_LOC
  DL_BYTES=$(echo "$JSON_OUTPUT" | jq -r '.download.bandwidth' 2>/dev/null)
  UL_BYTES=$(echo "$JSON_OUTPUT" | jq -r '.upload.bandwidth' 2>/dev/null)
  LATENCY=$(echo "$JSON_OUTPUT" | jq -r '.ping.latency' 2>/dev/null)
  SERVER_NAME=$(echo "$JSON_OUTPUT" | jq -r '.server.name' 2>/dev/null)
  SERVER_LOC=$(echo "$JSON_OUTPUT" | jq -r '.server.location' 2>/dev/null)
  
  local DL_MBPS UL_MBPS PING_MS
  DL_MBPS=$(awk "BEGIN {printf \"%.2f\", $DL_BYTES * 8 / 1000000}" 2>/dev/null || echo "0")
  UL_MBPS=$(awk "BEGIN {printf \"%.2f\", $UL_BYTES * 8 / 1000000}" 2>/dev/null || echo "0")
  PING_MS=$(awk "BEGIN {printf \"%.2f\", $LATENCY}" 2>/dev/null || echo "0")

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

# -------------------------
# FALLBACK HTTP METHOD (WGET/CURL)
# -------------------------
test_url_speed() {
    local url=$1
    local name=$2
    
    local wget_output
    wget_output=$(wget -4O /dev/null -T10 "$url" 2>&1)
    local speed_raw
    speed_raw=$(echo "$wget_output" | grep -oE '[0-9.]+\s?[KMG]B/s' | tail -1)
    local display_speed="Error"
    
    if [ -n "$speed_raw" ]; then
        local val unit
        val=$(echo "$speed_raw" | grep -oE '[0-9.]+')
        unit=$(echo "$speed_raw" | grep -oE '[KMG]B/s')
        
        if [[ "$unit" == *"GB/s"* ]]; then
            display_speed=$(echo "$val * 1024 * 8" | bc)
            display_speed="${display_speed} Mbps"
        elif [[ "$unit" == *"MB/s"* ]]; then
            display_speed=$(echo "$val * 8" | bc)
            display_speed="${display_speed} Mbps"
        elif [[ "$unit" == *"KB/s"* ]]; then
            display_speed=$(echo "scale=2; $val * 0.0078125" | bc)
            display_speed="${display_speed} Mbps"
        else
            display_speed="$speed_raw"
        fi
    fi

    # LOGIC: Upload = Download in Fallback mode
    local upload_speed="$display_speed"

    local domain
    domain=$(echo "$url" | awk -F'/' '{print $3}')
    local ping
    ping=$(ping -c1 -4 -W 2 "$domain" 2>/dev/null | awk -F'time=' '{print $2}' | cut -d ' ' -f 1 | tr -d '\r\n')
    
    if [ -z "$ping" ]; then ping="-"; else ping="${ping} ms"; fi
    
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
    
    local WIDTH=95
    printf "+%*s+\n" $((WIDTH - 6)) "" | tr ' ' '-'
}

# -------------------------
# SMART SPEEDTEST RUNNER
# -------------------------
check_outbound_port_8080() {
    local url="$CHECK_URL_8080"
    if curl -f -s -I --connect-timeout 5 "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

run_speedtest_all_official() {
  print_section_header "[ Network Speed Test ]"

  # If not installed earlier, install now (idempotent)
  if [ "$SPEEDTEST_INSTALLED" -eq 0 ]; then
    install_official_speedtest >/dev/null 2>&1 || true
    hash -r 2>/dev/null || true
  fi

  if check_outbound_port_8080; then
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

# -------------------------
# Upload result helpers
# -------------------------
extract_url_from_response() {
  grep -oE "https?://[^[:space:]\"'<>]+" | head -1 | tr -d '\r'
}

upload_to_custom_web() {
  local response
  response=$(curl -sS --fail --connect-timeout 15 --max-time 180 --retry 2 \
    -F "file=@${LOG_FILE};filename=benchmark.txt" "$CUSTOM_UPLOAD_URL" 2>/dev/null) || return 1
  echo "$response" | extract_url_from_response
}

upload_to_0x0() {
  local response
  response=$(curl -sS --fail --connect-timeout 15 --max-time 180 --retry 2 \
    -F "file=@${LOG_FILE};filename=benchmark.txt" https://0x0.st/ 2>/dev/null) || return 1
  echo "$response" | extract_url_from_response
}

upload_to_paste_rs() {
  local response
  response=$(curl -sS --fail --connect-timeout 15 --max-time 180 --retry 2 \
    --data-binary @"$LOG_FILE" https://paste.rs 2>/dev/null) || return 1
  echo "$response" | extract_url_from_response
}

upload_to_transfer_sh() {
  local response file_name
  file_name="benchmark-$(date +%Y%m%d-%H%M%S).txt"
  response=$(curl -sS --fail --connect-timeout 15 --max-time 180 --retry 2 \
    --upload-file "$LOG_FILE" "https://transfer.sh/$file_name" 2>/dev/null) || return 1
  echo "$response" | extract_url_from_response
}

upload_result_online() {
  local url service

  if [ ! -s "$LOG_FILE" ]; then
    echo "Log file not found or empty: $LOG_FILE" >&2
    return 1
  fi

  if [ -n "$CUSTOM_UPLOAD_URL" ]; then
    printf "  -> Trying custom web endpoint ... " >&2
    url=$(upload_to_custom_web) || true
    if [[ "$url" =~ ^https?:// ]]; then
      echo -e "${GREEN}OK${RESET}" >&2
      echo "$url"
      return 0
    fi
    echo -e "${RED}FAILED${RESET}" >&2
  fi

  for service in "0x0.st" "paste.rs" "transfer.sh"; do
    printf "  -> Trying %s ... " "$service" >&2
    url=""
    case "$service" in
      "0x0.st") url=$(upload_to_0x0) || true ;;
      "paste.rs") url=$(upload_to_paste_rs) || true ;;
      "transfer.sh") url=$(upload_to_transfer_sh) || true ;;
    esac

    if [[ "$url" =~ ^https?:// ]]; then
      echo -e "${GREEN}OK${RESET}" >&2
      echo "$url"
      return 0
    fi
    echo -e "${RED}FAILED${RESET}" >&2
  done

  return 1
}

# -------------------------
# MAIN
# -------------------------
main() {
  echo "Begin Install Package"
  clear
  
  # Install dependencies silently before logging so install messages are not included in the result.
  install_all >/dev/null 2>&1

  # Start tee logging so output still shows on SSH and overwrites LOG_FILE for this run only.
  # Save original stdout/stderr so upload messages can be kept out of LOG_FILE later.
  exec 3>&1 4>&2
  exec > >(tee "$LOG_FILE") 2>&1

  # Run tests (only benchmark output is written to LOG_FILE)
  get_system_info
  display_system_info

  run_dd_test
  run_fio_test
  run_ioping_test

  # Network tests
  run_speedtest_all_official

  # Stop logging before upload so upload status/link is not included in benchmark_result.txt.
  exec 1>&3 2>&4
  exec 3>&- 4>&-

  ONLINE_URL=$(upload_result_online 2>/dev/null) || ONLINE_URL=""
  echo ""
  echo "=== RESULT ONLINE ==="
  if [ -n "$ONLINE_URL" ]; then
    echo "$ONLINE_URL"
  else
    echo "Upload failed. Local file: $LOG_FILE"
  fi
}

# Run main
main "$@"
