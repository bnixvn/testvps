#!/bin/bash

# Colors
GREEN="\033[0;32m"
PINK="\033[0;35m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Table width configuration
TABLE_WIDTH=102
COL1_WIDTH=35
COL2_WIDTH=72

print_line() {
  printf "+%*s+\n" $((TABLE_WIDTH - 2)) "" | tr ' ' '-'
}

print_center_box() {
  local text="$1"
  local width=$TABLE_WIDTH
  local padding=$(( (width - ${#text} - 2) / 2 ))
  local extra=$(( (width - ${#text} - 2) % 2 ))
  printf "${GREEN}%*s%s%*s${RESET}\n\n" $padding "" "$text" $((padding + extra)) ""
  print_line
}

print_kv_row() {
  local key="$1"
  local value="$2"
  printf "| ${CYAN}%-*s${RESET} | %-*b \n" $((COL1_WIDTH - 2)) "$key" $((COL2_WIDTH - 2)) "$value"
  print_line
}

print_section_header() {
  echo
  print_center_box "$1"
}

# Check required tools
check_dependencies() {
  local deps=("bc" "fio" "ioping" "jq")
  local missing=()
  
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing+=("$dep")
    fi
  done
  
  if [ ${#missing[@]} -ne 0 ]; then
    echo "Installing missing dependencies: ${missing[*]}"
    if command -v apt >/dev/null; then
      sudo apt update && sudo apt install -y "${missing[@]}"
    elif command -v dnf >/dev/null; then
      sudo dnf install -y "${missing[@]}"
    elif command -v yum >/dev/null; then
      sudo yum install -y "${missing[@]}"
    else
      echo "Package manager not found. Please install manually: ${missing[*]}"
      exit 1
    fi
  fi
}

# System information functions
get_system_info() {
  # OS info
  if [ -f /etc/os-release ]; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  else
    OS_NAME=$(uname -srv)
  fi

  # CPU info
  CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//' | head -1)
  CPU_CORES=$(nproc)
  CPU_MHZ=$(lscpu | awk '/MHz/ {print $3; exit}')
  
  # CPU usage (more accurate method)
  CPU_IDLE=$(top -bn2 | grep "Cpu(s)" | tail -1 | awk -F',' '{print $4}' | awk '{print $1}')
  CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")

  # Memory info
  RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
  RAM_USED=$(free -h | awk '/Mem:/ {print $3}')
  RAM_FREE=$(free -h | awk '/Mem:/ {print $4}')
  RAM_USAGE_PCT=$(free | awk '/Mem:/ {printf "%.0f%%", $3/$2 * 100}')

  SWAP_TOTAL=$(free -h | awk '/Swap:/ {print $2}')
  SWAP_USED=$(free -h | awk '/Swap:/ {print $3}')

  # Disk info
  DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
  DISK_USED=$(df -h / | awk 'NR==2{print $3}')
  DISK_FREE=$(df -h / | awk 'NR==2{print $4}')
  DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')

  # System info
  ARCH=$(uname -m)
  KERNEL=$(uname -r)
  
  # Virtualization
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt)
    [ "$VIRT" = "none" ] && VIRT="Physical"
  else
    VIRT="Unknown"
  fi

  # Uptime
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
  
  print_kv_row "Operating System" "$OS_NAME"
  print_kv_row "Architecture" "$ARCH"
  print_kv_row "Kernel Version" "$KERNEL"
  print_kv_row "Virtualization" "$VIRT"
  print_kv_row "Processor" "$CPU_MODEL"
  print_kv_row "CPU Cores" "${CPU_CORES} Core(s) @ ${CPU_MHZ} MHz"
  print_kv_row "CPU Usage" "${GREEN}${CPU_USAGE}%${RESET}"
  print_kv_row "System Uptime" "$UPTIME_STR"
  print_kv_row "Load Average" "$LOADAVG"
  print_kv_row "Memory" "${RAM_TOTAL} Total (Used: ${GREEN}${RAM_USED}${RESET} - Free: ${RAM_FREE} - Usage: ${GREEN}${RAM_USAGE_PCT}${RESET})"
  print_kv_row "Swap" "${SWAP_TOTAL} Total (Used: ${SWAP_USED})"
  print_kv_row "Disk (Root)" "${DISK_TOTAL} Total (Used: ${DISK_USED} - Free: ${DISK_FREE} - Usage: ${DISK_USAGE})"
}

# DD test functions
run_dd_test() {
  print_section_header "[ DD Sequential Write Test ]"

  DD_SPEEDS=()
  
  # In header bảng
  printf "| %-7s | %-15s |\n" "Round" "Speed"
  print_line
  
  for i in 1 2 3; do
    # Chạy dd test
    OUT=$(dd if=/dev/zero of=testfile_$i bs=4M count=256 oflag=direct 2>&1)

    # Lấy tốc độ
    speed=$(echo "$OUT" | grep -oE '[0-9]+(\.[0-9]+)?\s*[GMK]?B/s' | head -1)
    speed_num=$(echo "$speed" | grep -oE '[0-9]+(\.[0-9]+)?')
    speed_unit=$(echo "$speed" | grep -oE '[GMK]?B/s')

    # Chuyển về MB/s
    case "$speed_unit" in
      GB/s) speed_mb=$(echo "$speed_num * 1024" | bc -l) ;;
      MB/s) speed_mb=$speed_num ;;
      KB/s) speed_mb=$(echo "$speed_num / 1024" | bc -l) ;;
      *) speed_mb=0 ;;
    esac

    DD_SPEEDS+=("$speed_mb")

    # In dòng kết quả round i
    printf "| %-7s | ${GREEN}%-15s${RESET} |\n" "Round $i" "$speed"
  done

  rm -f testfile_1 testfile_2 testfile_3

  # Tính tốc độ trung bình
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

  print_line
  printf "| %-7s | ${GREEN}%-15s${RESET} |\n" "Average" "$avg_txt"
  print_line
}

# FIO test functions
run_fio_test() {
  print_section_header "[ FIO Random Read/Write Test ]"

  CPU_CORES=$(nproc)
  NUMJOBS=$(( CPU_CORES > 8 ? 8 : CPU_CORES ))  # Giới hạn max 8 jobs
  IODEPTH=$(( NUMJOBS * 2 ))
  (( IODEPTH > 16 )) && IODEPTH=16

  BLOCK_SIZES=("4k" "16k" "64k" "256k" "1M")

  # In header bảng
  printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
         "Block Size" "Total Throughput" "Read Speed" "Write Speed" "Total IOPS" "Read IOPS" "Write IOPS"
  print_line

  for BS in "${BLOCK_SIZES[@]}"; do

    # Chạy fio
    fio --name=fio_test --ioengine=libaio --rw=randrw --bs=$BS --direct=1 \
        --size=512M --numjobs=$NUMJOBS --iodepth=$IODEPTH --runtime=15 \
        --time_based --group_reporting=1 --output-format=json > fio_tmp.json 2>&1

    if [ ! -s fio_tmp.json ] || ! jq -e . > /dev/null 2>&1 < fio_tmp.json; then
      # Nếu lỗi thì ghi dòng báo lỗi
      printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
             "$BS" "Test failed" "-" "-" "-" "-" "-"
      continue
    fi

    # Lấy số liệu
    RD_BW=$(jq '[.jobs[].read.bw] | add' fio_tmp.json 2>/dev/null || echo "0")
    WR_BW=$(jq '[.jobs[].write.bw] | add' fio_tmp.json 2>/dev/null || echo "0")
    RD_IOPS=$(jq '[.jobs[].read.iops] | add' fio_tmp.json 2>/dev/null || echo "0")
    WR_IOPS=$(jq '[.jobs[].write.iops] | add' fio_tmp.json 2>/dev/null || echo "0")

    # Chuyển bandwidth từ KB/s sang MB/s
    RD_MB=$(awk "BEGIN {printf \"%.0f\", $RD_BW / 1024}")
    WR_MB=$(awk "BEGIN {printf \"%.0f\", $WR_BW / 1024}")
    TOT_MB=$(( RD_MB + WR_MB ))

    # Hiển thị throughput với đơn vị MB/s hoặc GB/s nếu > 1024
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

    # Tính tổng IOPS
    IOPS_TOTAL=$(awk "BEGIN {printf \"%d\", ($RD_IOPS + $WR_IOPS)}")

    # Format IOPS hiển thị
    if (( IOPS_TOTAL >= 1000000 )); then
      IOPS_DISPLAY=$(awk "BEGIN {printf \"%.1fM\", $IOPS_TOTAL/1000000}")
    elif (( IOPS_TOTAL >= 1000 )); then
      IOPS_DISPLAY=$(awk "BEGIN {printf \"%.1fk\", $IOPS_TOTAL/1000}")
    else
      IOPS_DISPLAY=$IOPS_TOTAL
    fi

    RD_IOPS_INT=${RD_IOPS%.*}
    WR_IOPS_INT=${WR_IOPS%.*}

    # In kết quả dòng
    printf "| %-10s | %-16s | %-12s | %-12s | %-11s | %-9s | %-10s |\n" \
           "$BS" "$TOT_DISPLAY" "$RD_DISPLAY" "$WR_DISPLAY" "$IOPS_DISPLAY" "$RD_IOPS_INT" "$WR_IOPS_INT"

  done

  print_line
  rm -f fio_tmp.json fio_test.* 2>/dev/null
}

# IOPing latency test
run_ioping_test() {
  print_section_header "[ IOPing Latency Test ]"

  if ! command -v ioping >/dev/null 2>&1; then
    print_kv_row "Disk Latency" "${RED}ioping not available${RESET}"
    return
  fi

  LATENCY_RESULT=$(ioping -c 10 . 2>&1)
  RET=$?

  if [ $RET -ne 0 ]; then
    print_kv_row "Disk Latency" "${RED}ioping test failed${RESET}"
    echo -e "${RED}ioping output:${RESET}\n$LATENCY_RESULT" >&2
    return
  fi

  LATENCY_LINE=$(echo "$LATENCY_RESULT" | grep -E 'min/avg/max/mdev')
  if [ -z "$LATENCY_LINE" ]; then
    print_kv_row "Disk Latency" "${RED}Could not parse latency${RESET}"
    return
  fi

  # Lấy phần sau dấu '='
  VALUES=$(echo "$LATENCY_LINE" | awk -F'= ' '{print $2}')

  # Tách từng phần theo dấu '/'
  # Mỗi phần có dạng "129.5 us", nên ta dùng sed để xóa khoảng trắng
  # rồi tách theo '/' chính xác
  IFS='/' read -r MIN_LAT AVG_LAT MAX_LAT MDEV_LAT <<< "$VALUES"

  # Loại bỏ khoảng trắng 2 đầu
  MIN_LAT=$(echo "$MIN_LAT" | xargs)
  AVG_LAT=$(echo "$AVG_LAT" | xargs)
  MAX_LAT=$(echo "$MAX_LAT" | xargs)
  MDEV_LAT=$(echo "$MDEV_LAT" | xargs)

  print_kv_row "Average Latency" "${GREEN}${AVG_LAT}${RESET}"
  print_kv_row "Minimum Latency" "${MIN_LAT}"
  print_kv_row "Maximum Latency" "${MAX_LAT}"
}

# Main execution
main() {
  clear
  echo -e "${CYAN}System Benchmark Tool${RESET}"
  echo -e "${YELLOW}Starting comprehensive system tests...${RESET}\n"
  
  # Check and install dependencies
  check_dependencies
  
  # System information
  get_system_info
  display_system_info
  
  # Performance tests
  run_dd_test
  run_fio_test
  run_ioping_test
  
  echo -e "\n${GREEN}All tests completed successfully!${RESET}"
}

# Run main function
main "$@"
