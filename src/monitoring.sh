#!/bin/bash
#
# Cloud Deploy - 监控函数库
# 版本: 3.0.0
#

# 加载工具函数
SCRIPT_DIR_MONITOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR_MONITOR}/utils.sh" ] && source "${SCRIPT_DIR_MONITOR}/utils.sh"

# ============================================
# 健康检查
# ============================================

# HTTP 健康检查
health_check_http() {
    local url=$1
    local expected_status=${2:-200}
    local timeout=${3:-10}
    local method=${4:-"GET"}

    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X "${method}" \
        --max-time "${timeout}" \
        "${url}" 2>/dev/null)

    [ "${response}" = "${expected_status}" ]
}

# TCP 端口健康检查
health_check_tcp() {
    local host=$1
    local port=$2
    local timeout=${3:-5}

    check_port "${host}" "${port}" "${timeout}"
}

# Docker 容器健康检查
health_check_docker() {
    local container_name=$1

    local status=$(docker inspect --format='{{.State.Status}}' "${container_name}" 2>/dev/null)
    [ "${status}" = "running" ]
}

# 进程健康检查
health_check_process() {
    local process_name=$1

    pgrep -f "${process_name}" > /dev/null 2>&1
}

# 综合健康检查
health_check() {
    local type=$1
    local target=$2
    local expected=${3:-""}
    local timeout=${4:-10}

    case ${type} in
        http)
            health_check_http "${target}" "${expected:-200}" "${timeout}"
            ;;
        tcp)
            local host=$(echo "${target}" | cut -d: -f1)
            local port=$(echo "${target}" | cut -d: -f2)
            health_check_tcp "${host}" "${port}" "${timeout}"
            ;;
        docker)
            health_check_docker "${target}"
            ;;
        process)
            health_check_process "${target}"
            ;;
        *)
            log_error "未知健康检查类型: ${type}"
            return 1
            ;;
    esac
}

# 等待服务健康
wait_for_healthy() {
    local type=$1
    local target=$2
    local timeout=${3:-60}
    local interval=${4:-2}
    local expected=${5:-""}

    log_info "等待服务健康: ${target}"

    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    local attempt=1

    while [ $(date +%s) -lt ${end_time} ]; do
        if health_check "${type}" "${target}" "${expected}"; then
            log_info "服务已健康: ${target} (尝试 ${attempt} 次)"
            return 0
        fi

        log_debug "健康检查失败，等待 ${interval} 秒... (尝试 ${attempt})"
        sleep ${interval}
        attempt=$((attempt + 1))
    done

    log_error "服务健康检查超时: ${target} (${timeout}秒)"
    return 1
}

# 详细健康检查报告
health_check_report() {
    local target=$1
    local type=${2:-"http"}

    log_info "生成健康检查报告: ${target}"

    local report="========================================\n"
    report+="健康检查报告\n"
    report+="========================================\n\n"
    report+="目标: ${target}\n"
    report+="类型: ${type}\n"
    report+="时间: $(date '+%Y-%m-%d %H:%M:%S')\n\n"

    case ${type} in
        http)
            local response=$(curl -s -w "\n%{http_code}\n%{time_total}\n%{size_download}" \
                --max-time 10 "${target}" 2>/dev/null)

            local http_code=$(echo "${response}" | tail -3 | head -1)
            local time_total=$(echo "${response}" | tail -2 | head -1)
            local size=$(echo "${response}" | tail -1)

            report+="HTTP 状态码: ${http_code}\n"
            report+="响应时间: ${time_total} 秒\n"
            report+="响应大小: ${size} 字节\n"
            report+="状态: $([ "${http_code}" = "200" ] && echo "✅ 正常" || echo "❌ 异常")\n"
            ;;
        tcp)
            local host=$(echo "${target}" | cut -d: -f1)
            local port=$(echo "${target}" | cut -d: -f2)

            if check_port "${host}" "${port}"; then
                report+="端口状态: ✅ 开放\n"
            else
                report+="端口状态: ❌ 关闭\n"
            fi
            ;;
    esac

    echo -e "${report}"
}

# ============================================
# 系统监控
# ============================================

# 获取系统负载
get_system_load() {
    if [ -f /proc/loadavg ]; then
        cat /proc/loadavg | awk '{print $1, $2, $3}'
    else
        uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//'
    fi
}

# 获取 CPU 使用率
get_cpu_usage() {
    local interval=${1:-1}

    if command -v mpstat &> /dev/null; then
        mpstat ${interval} 1 | awk '/Average/ {print 100 - $NF}'
    elif [ -f /proc/stat ]; then
        # 从 /proc/stat 计算
        local cpu1=($(head -1 /proc/stat))
        sleep ${interval}
        local cpu2=($(head -1 /proc/stat))

        local idle1=${cpu1[4]}
        local idle2=${cpu2[4]}
        local total1=0
        local total2=0

        for i in "${cpu1[@]:1}"; do total1=$((total1 + i)); done
        for i in "${cpu2[@]:1}"; do total2=$((total2 + i)); done

        local total_diff=$((total2 - total1))
        local idle_diff=$((idle2 - idle1))

        if [ ${total_diff} -gt 0 ]; then
            echo "scale=1; (${total_diff} - ${idle_diff}) * 100 / ${total_diff}" | bc
        else
            echo "0"
        fi
    else
        echo "unknown"
    fi
}

# 获取内存使用情况
get_memory_usage() {
    if [ -f /proc/meminfo ]; then
        local total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        local available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)

        if [ -z "${available}" ]; then
            available=$(awk '/MemFree/ {print $2}' /proc/meminfo)
            local buffers=$(awk '/Buffers/ {print $2}' /proc/meminfo)
            local cached=$(awk '/^Cached/ {print $2}' /proc/meminfo)
            available=$((available + buffers + cached))
        fi

        local used=$((total - available))
        local percentage=$((used * 100 / total))

        echo "${used} ${total} ${percentage}"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        local total=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024)}')
        local used=$(vm_stat | awk '/Pages active/ {print $3}' | sed 's/\.//' | awk '{print int($1 * 4096 / 1024 / 1024)}')
        local percentage=$((used * 100 / total))
        echo "${used} ${total} ${percentage}"
    else
        echo "0 0 0"
    fi
}

# 获取磁盘使用情况
get_disk_usage() {
    local path=${1:-"/"}

    df -h "${path}" | awk 'NR==2 {print $3, $2, $5}'
}

# 获取网络流量
get_network_traffic() {
    local interface=${1:-"eth0"}
    local interval=${2:-1}

    if [ -f /proc/net/dev ]; then
        local rx1=$(awk "/${interface}/ {print \$2}" /proc/net/dev)
        local tx1=$(awk "/${interface}/ {print \$10}" /proc/net/dev)

        sleep ${interval}

        local rx2=$(awk "/${interface}/ {print \$2}" /proc/net/dev)
        local tx2=$(awk "/${interface}/ {print \$10}" /proc/net/dev)

        local rx_rate=$(( (rx2 - rx1) / interval ))
        local tx_rate=$(( (tx2 - tx1) / interval ))

        echo "${rx_rate} ${tx_rate}"
    else
        echo "0 0"
    fi
}

# 获取系统信息快照
get_system_snapshot() {
    local output="========================================\n"
    output+="系统监控快照\n"
    output+="========================================\n\n"

    # CPU 信息
    output+="CPU:\n"
    output+="  核心数: $(get_cpu_cores)\n"
    output+="  使用率: $(get_cpu_usage 1)%\n"
    output+="  负载: $(get_system_load)\n\n"

    # 内存信息
    local mem_info=($(get_memory_usage))
    output+="内存:\n"
    output+="  已用: ${mem_info[0]}MB\n"
    output+="  总计: ${mem_info[1]}MB\n"
    output+="  使用率: ${mem_info[2]}%\n\n"

    # 磁盘信息
    local disk_info=($(get_disk_usage "/"))
    output+="磁盘:\n"
    output+="  已用: ${disk_info[0]}\n"
    output+="  总计: ${disk_info[1]}\n"
    output+="  使用率: ${disk_info[2]}\n\n"

    # 系统信息
    output+="系统:\n"
    output+="  主机名: $(get_hostname)\n"
    output+="  架构: $(get_arch)\n"
    output+="  操作系统: $(get_os_info)\n"
    output+="  IP 地址: $(get_ip_address)\n"

    echo -e "${output}"
}

# ============================================
# 远程监控
# ============================================

# 远程系统监控
remote_monitor() {
    local host=$1
    local user=$2
    local password=$3

    log_info "获取远程系统信息: ${host}"

    ssh_connect "${host}" "${user}" "${password}" "
        echo '=== 系统信息 ==='
        echo \"主机名: \$(hostname)\"
        echo \"系统: \$(uname -a)\"
        echo \"IP: \$(hostname -I | awk '{print \$1}')\"

        echo ''
        echo '=== CPU ==='
        echo \"核心数: \$(nproc)\"
        echo \"负载: \$(cat /proc/loadavg | awk '{print \$1, \$2, \$3}')\"

        echo ''
        echo '=== 内存 ==='
        free -h | head -2

        echo ''
        echo '=== 磁盘 ==='
        df -h / | tail -1

        echo ''
        echo '=== Docker ==='
        if command -v docker &> /dev/null; then
            echo \"Docker 版本: \$(docker --version)\"
            echo '运行容器:'
            docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        else
            echo 'Docker 未安装'
        fi
    "
}

# 检查远程服务状态
remote_service_check() {
    local host=$1
    local user=$2
    local password=$3
    local service=$4

    ssh_connect "${host}" "${user}" "${password}" "
        if command -v systemctl &> /dev/null; then
            systemctl is-active ${service} 2>/dev/null || echo 'inactive'
        elif command -v docker &> /dev/null; then
            docker ps --format '{{.Names}}' | grep -q ${service} && echo 'running' || echo 'stopped'
        else
            echo 'unknown'
        fi
    "
}

# ============================================
# 资源告警
# ============================================

# 检查资源阈值
check_resource_threshold() {
    local cpu_threshold=${1:-80}
    local memory_threshold=${2:-80}
    local disk_threshold=${3:-90}

    local alerts=""

    # 检查 CPU
    local cpu_usage=$(get_cpu_usage 1)
    if [ "${cpu_usage}" != "unknown" ] && [ "$(echo "${cpu_usage} > ${cpu_threshold}" | bc 2>/dev/null)" = "1" ]; then
        alerts+="CPU 使用率过高: ${cpu_usage}%\n"
    fi

    # 检查内存
    local mem_info=($(get_memory_usage))
    if [ "${mem_info[2]}" -gt "${memory_threshold}" ] 2>/dev/null; then
        alerts+="内存使用率过高: ${mem_info[2]}%\n"
    fi

    # 检查磁盘
    local disk_info=($(get_disk_usage "/"))
    local disk_percent=$(echo "${disk_info[2]}" | sed 's/%//')
    if [ "${disk_percent}" -gt "${disk_threshold}" ] 2>/dev/null; then
        alerts+="磁盘使用率过高: ${disk_info[2]}\n"
    fi

    if [ -n "${alerts}" ]; then
        echo -e "${alerts}"
        return 1
    fi

    return 0
}

# 资源告警通知
resource_alert() {
    local cpu_threshold=${1:-80}
    local memory_threshold=${2:-80}
    local disk_threshold=${3:-90}

    local alerts=$(check_resource_threshold "${cpu_threshold}" "${memory_threshold}" "${disk_threshold}")

    if [ -n "${alerts}" ]; then
        log_warn "资源告警:\n${alerts}"

        # 发送告警通知
        if type send_all_notifications &> /dev/null; then
            send_all_notifications "warning" "资源告警" "${alerts}"
        fi

        return 1
    fi

    return 0
}

# ============================================
# 持续监控
# ============================================

# 持续监控循环
monitor_loop() {
    local interval=${1:-60}
    local duration=${2:-0}  # 0 = 无限
    local callback=${3:-""}

    log_info "开始持续监控 (间隔: ${interval}秒, 持续: ${duration}秒)"

    local start_time=$(date +%s)
    local end_time=0
    [ ${duration} -gt 0 ] && end_time=$((start_time + duration))

    while true; do
        # 获取系统快照
        local snapshot=$(get_system_snapshot)

        # 检查资源阈值
        local alerts=$(check_resource_threshold)

        # 执行回调
        if [ -n "${callback}" ]; then
            eval "${callback}" "${snapshot}" "${alerts}"
        fi

        # 输出监控信息
        log_info "监控周期完成"
        [ -n "${alerts}" ] && log_warn "告警: ${alerts}"

        # 检查是否超时
        if [ ${end_time} -gt 0 ] && [ $(date +%s) -ge ${end_time} ]; then
            log_info "监控时间结束"
            break
        fi

        sleep ${interval}
    done
}

# 监控服务可用性
monitor_service() {
    local service_name=$1
    local check_type=$2
    local target=$3
    local interval=${4:-30}
    local max_failures=${5:-3}

    log_info "开始监控服务: ${service_name}"

    local failures=0

    while true; do
        if health_check "${check_type}" "${target}"; then
            failures=0
            log_debug "服务正常: ${service_name}"
        else
            failures=$((failures + 1))
            log_warn "服务异常: ${service_name} (连续失败: ${failures})"

            if [ ${failures} -ge ${max_failures} ]; then
                log_error "服务 ${service_name} 连续失败 ${failures} 次"

                # 发送告警
                if type send_all_notifications &> /dev/null; then
                    send_all_notifications "failure" "服务异常 - ${service_name}" \
                        "服务 ${service_name} 连续 ${failures} 次健康检查失败\n目标: ${target}"
                fi

                # 重置计数
                failures=0
            fi
        fi

        sleep ${interval}
    done
}

# ============================================
# 部署监控
# ============================================

# 部署后监控
post_deploy_monitor() {
    local host=$1
    local port=$2
    local path=${3:-"/"}
    local duration=${4:-300}
    local interval=${5:-10}

    log_info "开始部署后监控 (持续 ${duration}秒)..."

    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    local total_checks=0
    local failed_checks=0

    while [ $(date +%s) -lt ${end_time} ]; do
        total_checks=$((total_checks + 1))

        if ! health_check_http "http://${host}:${port}${path}"; then
            failed_checks=$((failed_checks + 1))
            log_warn "健康检查失败 (${failed_checks}/${total_checks})"
        fi

        sleep ${interval}
    done

    local success_rate=$(( (total_checks - failed_checks) * 100 / total_checks ))

    log_info "部署后监控完成:"
    log_info "  总检查次数: ${total_checks}"
    log_info "  失败次数: ${failed_checks}"
    log_info "  成功率: ${success_rate}%"

    # 如果成功率低于 99%，发送告警
    if [ ${success_rate} -lt 99 ]; then
        log_warn "服务可用性低于 99%"

        if type send_all_notifications &> /dev/null; then
            send_all_notifications "warning" "服务可用性告警" \
                "部署后监控成功率: ${success_rate}%\n失败次数: ${failed_checks}/${total_checks}"
        fi

        return 1
    fi

    return 0
}

# ============================================
# 日志监控
# ============================================

# 监控日志文件
monitor_log() {
    local log_file=$1
    local pattern=${2:-"ERROR|FATAL|Exception"}
    local callback=${3:-""}

    log_info "开始监控日志: ${log_file}"

    if [ ! -f "${log_file}" ]; then
        log_error "日志文件不存在: ${log_file}"
        return 1
    fi

    tail -f "${log_file}" | while read line; do
        if echo "${line}" | grep -qE "${pattern}"; then
            log_warn "日志告警: ${line}"

            if [ -n "${callback}" ]; then
                eval "${callback}" "${line}"
            fi
        fi
    done
}

# 远程日志监控
remote_log_monitor() {
    local host=$1
    local user=$2
    local password=$3
    local log_file=$4
    local pattern=${5:-"ERROR|FATAL"}

    log_info "开始远程日志监控: ${host}:${log_file}"

    ssh_connect "${host}" "${user}" "${password}" "tail -f ${log_file}" | while read line; do
        if echo "${line}" | grep -qE "${pattern}"; then
            log_warn "远程日志告警 [${host}]: ${line}"
        fi
    done
}

# 导出所有函数
export -f health_check_http health_check_tcp health_check_docker health_check_process
export -f health_check wait_for_healthy health_check_report
export -f get_system_load get_cpu_usage get_memory_usage get_disk_usage get_network_traffic
export -f get_system_snapshot
export -f remote_monitor remote_service_check
export -f check_resource_threshold resource_alert
export -f monitor_loop monitor_service post_deploy_monitor
export -f monitor_log remote_log_monitor
