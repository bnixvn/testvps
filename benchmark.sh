#!/bin/bash

RESULT_FILE="benchmark_result.txt"

echo "=== SYSTEM BENCHMARK RESULT ===" > "$RESULT_FILE"
echo "Generated: $(date)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

# ================================
#  SILENT INSTALL FUNCTION
# ================================
silent_install() {
    if command -v apt >/dev/null 2>&1; then
        sudo apt update >/dev/null 2>&1
        sudo apt install -y "$@" >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$@" >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$@" >/dev/null 2>&1
    fi
}

# ================================
#  INSTALL DEPENDENCIES
# ================================
echo "Installing dependencies..." | tee -a "$RESULT_FILE"
silent_install bc fio ioping jq wget curl

# ================================
#  INSTALL SPEEDTEST (OOKLA)
# ================================
install_speedtest() {
    if command -v speedtest >/dev/null 2>&1; then
        return
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    fi

    if [[ "$OS" == "ubuntu" && "$VER" == "24.04" ]]; then
        wget -qO - https://raw.githubusercontent.com/VadimBoev/speedtest-cli-ubuntu-24.04-LTS/main/install.sh \
            | sudo bash >/dev/null 2>&1
    elif command -v apt >/dev/null 2>&1; then
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh \
            | sudo bash >/dev/null 2>&1
        sudo apt install -y speedtest >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh \
            | sudo bash >/dev/null 2>&1
        sudo yum install -y speedtest >/dev/null 2>&1
    elif command -v snap >/dev/null 2>&1; then
        sudo snap install speedtest >/dev/null 2>&1
    fi
}

echo "Installing Speedtest..." | tee -a "$RESULT_FILE"
install_speedtest

# ================================
#  SYSTEM INFO
# ================================
echo "" >> "$RESULT_FILE"
echo "=== SYSTEM INFORMATION ===" >> "$RESULT_FILE"
uname -a >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
lscpu >> "$RESULT_FILE" 2>/dev/null
echo "" >> "$RESULT_FILE"
free -h >> "$RESULT_FILE" 2>/dev/null
echo "" >> "$RESULT_FILE"
df -h / >> "$RESULT_FILE" 2>/dev/null

# ================================
#  DD TEST
# ================================
echo "" >> "$RESULT_FILE"
echo "=== DD WRITE TEST ===" >> "$RESULT_FILE"
dd if=/dev/zero of=testfile bs=1G count=1 oflag=direct 2>> "$RESULT_FILE"
rm -f testfile

# ================================
#  FIO TEST
# ================================
echo "" >> "$RESULT_FILE"
echo "=== FIO RANDOM READ/WRITE TEST ===" >> "$RESULT_FILE"
fio --name=randtest --ioengine=libaio --rw=randrw --bs=4k --size=256M \
    --numjobs=4 --iodepth=8 --runtime=10 --time_based --group_reporting \
    >> "$RESULT_FILE" 2>&1
rm -f randtest.*

# ================================
#  IOPING TEST
# ================================
echo "" >> "$RESULT_FILE"
echo "=== IOPING LATENCY TEST ===" >> "$RESULT_FILE"
ioping -c 10 . >> "$RESULT_FILE" 2>&1

# ================================
#  SPEEDTEST
# ================================
echo "" >> "$RESULT_FILE"
echo "=== NETWORK SPEEDTEST ===" >> "$RESULT_FILE"
if command -v speedtest >/dev/null 2>&1; then
    speedtest --accept-license --accept-gdpr >> "$RESULT_FILE" 2>&1
else
    echo "Speedtest binary not available." >> "$RESULT_FILE"
fi

# ================================
#  UPLOAD TO GITHUB GIST (ANONYMOUS)
# ================================
echo "" >> "$RESULT_FILE"
echo "=== UPLOADING TO GITHUB GIST (ANONYMOUS) ===" >> "$RESULT_FILE"

CONTENT_JSON=$(jq -Rs . < "$RESULT_FILE")

GIST_RESPONSE=$(curl -s -X POST https://api.github.com/gists \
  -d "{\"files\": {\"benchmark.txt\": {\"content\": $CONTENT_JSON}}, \"public\": true}")

GIST_URL=$(echo "$GIST_RESPONSE" | jq -r '.html_url')

echo "Gist URL: $GIST_URL" | tee -a "$RESULT_FILE"

echo ""
echo "=== DONE ==="
echo "View your benchmark online:"
echo "$GIST_URL"
