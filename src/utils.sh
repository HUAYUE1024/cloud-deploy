#!/bin/bash
#
# Cloud Deploy - 工具函数库
# 版本: 3.0.0
#

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 日志级别
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# 当前日志级别
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level_num

    case $level in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO ;;
        WARN)  level_num=$LOG_LEVEL_WARN ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        *)     level_num=$LOG_LEVEL_INFO ;;
    esac

    # 检查日志级别
    if [ $level_num -lt $CURRENT_LOG_LEVEL ]; then
        return 0
    fi

    case $level in
        DEBUG) echo -e "${CYAN}[DEBUG]${NC} ${timestamp} - ${message}" ;;
        INFO)  echo -e "${GREEN}[INFO]${NC}  ${timestamp} - ${message}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}" ;;
    esac

    # 写入日志文件
    if [ -n "${LOG_FILE:-}" ] && [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[${level}] ${timestamp} - ${message}" >> "$LOG_FILE"
    fi
}

# 调试日志
log_debug() {
    log DEBUG "$@"
}

# 信息日志
log_info() {
    log INFO "$@"
}

# 警告日志
log_warn() {
    log WARN "$@"
}

# 错误日志
log_error() {
    log ERROR "$@"
}

# 审计日志
audit_log() {
    local action=$1
    local details=${2:-""}
    local user=${3:-$(whoami)}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ -n "${AUDIT_LOG_FILE:-}" ] && [ -d "$(dirname "$AUDIT_LOG_FILE")" ]; then
        echo "${timestamp}|${user}|${action}|${details}" >> "$AUDIT_LOG_FILE"
    fi
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_error "命令未找到: $cmd"
        return 1
    fi
    return 0
}

# 检查必需命令
check_required_commands() {
    local commands=("$@")
    local missing=()

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少必需命令: ${missing[*]}"
        return 1
    fi

    return 0
}

# 等待用户确认
confirm() {
    local message=${1:-"是否继续?"}
    local default=${2:-"y"}

    if [ "$default" = "y" ]; then
        read -p "$message [Y/n]: " choice
        choice=${choice:-y}
    else
        read -p "$message [y/N]: " choice
        choice=${choice:-n}
    fi

    [[ "$choice" =~ ^[Yy]$ ]]
}

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local width=${3:-50}
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\rProgress: ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %d%%" $percentage

    if [ $current -eq $total ]; then
        echo
    fi
}

# 重试函数
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local command="$@"
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if eval "$command"; then
            return 0
        fi

        log_warn "命令失败，${delay}秒后重试 (${attempt}/${max_attempts})..."
        sleep $delay
        attempt=$((attempt + 1))
    done

    log_error "命令在 ${max_attempts} 次尝试后仍然失败"
    return 1
}

# 超时执行
timeout_exec() {
    local timeout=$1
    shift
    local command="$@"

    # 使用 timeout 命令（如果可用）
    if command -v timeout &> /dev/null; then
        timeout "$timeout" bash -c "$command"
    else
        # 手动实现超时
        local pid
        eval "$command" &
        pid=$!

        # 等待指定时间
        (sleep $timeout && kill $pid 2>/dev/null) &
        local watchdog=$!

        wait $pid 2>/dev/null
        local exit_code=$?

        kill $watchdog 2>/dev/null
        return $exit_code
    fi
}

# 生成随机字符串
generate_random_string() {
    local length=${1:-16}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1
}

# 检查端口是否可用
check_port() {
    local host=$1
    local port=$2
    local timeout=${3:-5}

    if command -v nc &> /dev/null; then
        nc -z -w $timeout $host $port 2>/dev/null
    elif command -v timeout &> /dev/null; then
        timeout $timeout bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
    else
        bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
    fi
}

# 等待端口可用
wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-60}
    local interval=${4:-2}

    log_info "等待端口 $host:$port 可用..."

    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while [ $(date +%s) -lt $end_time ]; do
        if check_port $host $port; then
            log_info "端口 $host:$port 已可用"
            return 0
        fi
        sleep $interval
    done

    log_error "等待端口 $host:$port 超时"
    return 1
}

# 检查 URL 是否可访问
check_url() {
    local url=$1
    local timeout=${2:-10}

    curl -sf --max-time $timeout "$url" > /dev/null 2>&1
}

# 等待 URL 可访问
wait_for_url() {
    local url=$1
    local timeout=${2:-60}
    local interval=${3:-2}

    log_info "等待 URL 可访问: $url"

    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while [ $(date +%s) -lt $end_time ]; do
        if check_url $url; then
            log_info "URL 已可访问: $url"
            return 0
        fi
        sleep $interval
    done

    log_error "等待 URL 超时: $url"
    return 1
}

# 获取文件大小
get_file_size() {
    local file=$1

    if [ -f "$file" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            stat -f%z "$file"
        else
            stat -c%s "$file"
        fi
    else
        echo 0
    fi
}

# 格式化文件大小
format_file_size() {
    local size=$1

    if [ $size -ge 1073741824 ]; then
        echo "$(echo "scale=2; $size / 1073741824" | bc)G"
    elif [ $size -ge 1048576 ]; then
        echo "$(echo "scale=2; $size / 1048576" | bc)M"
    elif [ $size -ge 1024 ]; then
        echo "$(echo "scale=2; $size / 1024" | bc)K"
    else
        echo "${size}B"
    fi
}

# 计算时间差
time_diff() {
    local start=$1
    local end=$2
    local diff=$((end - start))

    if [ $diff -ge 3600 ]; then
        echo "$((diff / 3600))h $((diff % 3600 / 60))m $((diff % 60))s"
    elif [ $diff -ge 60 ]; then
        echo "$((diff / 60))m $((diff % 60))s"
    else
        echo "${diff}s"
    fi
}

# 清理临时文件
cleanup_temp() {
    local pattern=${1:-"/tmp/deploy-*"}

    if [ -d "/tmp" ]; then
        rm -rf $pattern 2>/dev/null
    fi
}

# 创建临时目录
create_temp_dir() {
    local prefix=${1:-"deploy"}
    mktemp -d "/tmp/${prefix}-XXXXXX"
}

# 锁定文件
acquire_lock() {
    local lock_file=$1
    local timeout=${2:-30}

    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while [ $(date +%s) -lt $end_time ]; do
        if (set -o noclobber; echo $$ > "$lock_file") 2>/dev/null; then
            trap 'release_lock "'"$lock_file"'"' EXIT
            return 0
        fi

        # 检查锁定进程是否还存在
        local lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [ -n "$lock_pid" ] && ! kill -0 $lock_pid 2>/dev/null; then
            rm -f "$lock_file"
            continue
        fi

        sleep 1
    done

    log_error "获取锁超时: $lock_file"
    return 1
}

# 释放锁
release_lock() {
    local lock_file=$1
    rm -f "$lock_file"
}

# 检查是否为 root 用户
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# 获取当前用户
get_current_user() {
    whoami
}

# 获取主机名
get_hostname() {
    hostname -f 2>/dev/null || hostname
}

# 获取 IP 地址
get_ip_address() {
    if command -v ip &> /dev/null; then
        ip route get 1 2>/dev/null | awk '{print $7; exit}'
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1
    else
        echo "unknown"
    fi
}

# 获取操作系统信息
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME $VERSION"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo "$DISTRIB_DESCRIPTION"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS $(sw_vers -productVersion)"
    else
        echo "Unknown"
    fi
}

# 获取系统架构
get_arch() {
    uname -m
}

# 获取 CPU 核心数
get_cpu_cores() {
    nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}

# 获取内存大小（MB）
get_memory_size() {
    if [ -f /proc/meminfo ]; then
        awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$(($(sysctl -n hw.memsize) / 1024 / 1024))"
    else
        echo "0"
    fi
}

# 获取磁盘空间（MB）
get_disk_space() {
    local path=${1:-"/"}
    df -m "$path" | awk 'NR==2 {print $4}'
}

# 检查系统资源
check_system_resources() {
    local min_memory=${1:-512}  # MB
    local min_disk=${2:-1024}   # MB

    local memory=$(get_memory_size)
    local disk=$(get_disk_space)

    if [ "$memory" -lt "$min_memory" ]; then
        log_warn "内存不足: ${memory}MB (最少需要 ${min_memory}MB)"
    fi

    if [ "$disk" -lt "$min_disk" ]; then
        log_warn "磁盘空间不足: ${disk}MB (最少需要 ${min_disk}MB)"
    fi
}

# 加密字符串（简单加密，不用于安全场景）
encrypt_string() {
    local string=$1
    local key=${2:-"cloud-deploy"}
    echo -n "$string" | openssl enc -aes-256-cbc -a -salt -pass pass:$key 2>/dev/null
}

# 解密字符串
decrypt_string() {
    local encrypted=$1
    local key=${2:-"cloud-deploy"}
    echo -n "$encrypted" | openssl enc -aes-256-cbc -a -d -salt -pass pass:$key 2>/dev/null
}

# 生成 UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        generate_random_string 32
    fi
}

# 比较版本号
version_compare() {
    local version1=$1
    local version2=$2

    if [[ "$version1" == "$version2" ]]; then
        echo "0"
        return
    fi

    local IFS=.
    local i ver1=($version1) ver2=($version2)

    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            echo "1"
            return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            echo "-1"
            return
        fi
    done

    echo "0"
}

# 检查是否为有效 IP
is_valid_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ $ip =~ $valid_ip_regex ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 检查是否为有效域名
is_valid_domain() {
    local domain=$1
    local valid_domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

    [[ $domain =~ $valid_domain_regex ]]
}

# URL 编码
url_encode() {
    local string=$1
    python3 -c "import urllib.parse; print(urllib.parse.quote('$string'))" 2>/dev/null || \
    echo "$string" | sed 's/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/\&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/\*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/\//%2F/g; s/:/%3A/g; s/;/%3B/g; s//%3E/g; s/?/%3F/g; s/@/%40/g; s/\[/%5B/g; s/\\/%5C/g; s/\]/%5D/g; s/\^/%5E/g; s/`/%60/g; s/{/%7B/g; s/|/%7C/g; s/}/%7D/g; s/~/%7E/g'
}

# URL 解码
url_decode() {
    local string=$1
    python3 -c "import urllib.parse; print(urllib.parse.unquote('$string'))" 2>/dev/null || \
    echo "$string" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g'
}

# JSON 查询（不依赖 jq）
json_get() {
    local json=$1
    local key=$2

    if command -v jq &> /dev/null; then
        echo "$json" | jq -r ".$key" 2>/dev/null
    else
        # 简单的 JSON 解析
        echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4
    fi
}

# 导出所有函数
export -f log log_debug log_info log_warn log_error audit_log
export -f check_command check_required_commands confirm
export -f show_progress retry timeout_exec
export -f generate_random_string check_port wait_for_port
export -f check_url wait_for_url
export -f get_file_size format_file_size time_diff
export -f cleanup_temp create_temp_dir
export -f acquire_lock release_lock
export -f is_root get_current_user get_hostname get_ip_address
export -f get_os_info get_arch get_cpu_cores get_memory_size get_disk_space
export -f check_system_resources
export -f encrypt_string decrypt_string generate_uuid
export -f version_compare is_valid_ip is_valid_domain
export -f url_encode url_decode json_get
