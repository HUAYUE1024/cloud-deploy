#!/bin/bash
#
# Cloud Deploy - 企业级多云部署平台
# 版本: 3.0.0
# 作者: HUAYUE1024
# 仓库: https://github.com/HUAYUE1024/cloud-deploy
#

set -euo pipefail

# ============================================
# 配置和常量
# ============================================

readonly VERSION="3.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${DEPLOY_CONFIG:-$HOME/.deploy-tools/config.yaml}"
readonly LOG_DIR="/var/log/deploy"
readonly AUDIT_LOG="${LOG_DIR}/audit.log"
readonly LOCK_FILE="/tmp/deploy.lock"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ============================================
# 工具函数
# ============================================

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC}  ${timestamp} - ${message}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}" ;;
        DEBUG) echo -e "${CYAN}[DEBUG]${NC} ${timestamp} - ${message}" ;;
        *)     echo -e "${timestamp} - ${message}" ;;
    esac

    # 写入日志文件
    if [ -d "${LOG_DIR}" ]; then
        echo "[${level}] ${timestamp} - ${message}" >> "${LOG_DIR}/deploy.log"
    fi
}

# 审计日志
audit_log() {
    local action=$1
    local user=${2:-$(whoami)}
    local details=${3:-""}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ -d "${LOG_DIR}" ]; then
        echo "${timestamp}|${user}|${action}|${details}" >> "${AUDIT_LOG}"
    fi
}

# 错误处理
error_handler() {
    local line_no=$1
    local error_code=$2
    log ERROR "脚本执行失败，行号: ${line_no}, 错误码: ${error_code}"

    # 发送失败通知
    send_notification "failure" "部署失败" "错误发生在第 ${line_no} 行，错误码: ${error_code}"

    # 清理资源
    cleanup

    exit ${error_code}
}

trap 'error_handler ${LINENO} $?' ERR

# 清理函数
cleanup() {
    log INFO "执行清理操作..."

    # 释放锁
    rm -f "${LOCK_FILE}"

    # 清理临时文件
    rm -rf /tmp/deploy-*

    # 停止后台进程
    if [ -n "${BACKGROUND_PID:-}" ]; then
        kill "${BACKGROUND_PID}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# 加载配置
load_config() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        log WARN "配置文件不存在: ${CONFIG_FILE}，使用默认配置"
        CONFIG="{}"
        return 0
    fi

    # 检查 yq 是否安装
    if command -v yq &> /dev/null; then
        CONFIG=$(cat "${CONFIG_FILE}")
    else
        # 如果没有 yq，尝试使用简单的配置解析
        log WARN "yq 未安装，使用简化配置解析"
        CONFIG="{}"
    fi
}

# 获取配置值
get_config() {
    local path=$1
    local default=${2:-""}

    if command -v yq &> /dev/null; then
        local value=$(echo "${CONFIG}" | yq "${path}" - 2>/dev/null)

        if [ "${value}" = "null" ] || [ -z "${value}" ]; then
            echo "${default}"
        else
            echo "${value}"
        fi
    else
        echo "${default}"
    fi
}

# 环境变量替换
replace_env_vars() {
    local input=$1

    # 替换 ${VAR} 格式的环境变量
    echo "${input}" | sed -e 's|\${\([^}]*\)}|${\1:-}|g' | envsubst
}

# ============================================
# SSH 和远程执行
# ============================================

# SSH 连接函数
ssh_connect() {
    local host=$1
    local user=$2
    local password=$3
    shift 3
    local cmd="$*"

    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

    if command -v sshpass &> /dev/null; then
        sshpass -p "${password}" ssh ${ssh_opts} "${user}@${host}" "${cmd}"
    else
        ssh ${ssh_opts} "${user}@${host}" "${cmd}"
    fi
}

# SCP 传输函数
scp_upload() {
    local host=$1
    local user=$2
    local password=$3
    local src=$4
    local dst=$5

    local scp_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -r"

    if command -v sshpass &> /dev/null; then
        sshpass -p "${password}" scp ${scp_opts} "${src}" "${user}@${host}:${dst}"
    else
        scp ${scp_opts} "${src}" "${user}@${host}:${dst}"
    fi
}

# ============================================
# 项目检测和构建
# ============================================

# 检测项目类型
detect_project_type() {
    log INFO "检测项目类型..."

    if [ -f "package.json" ]; then
        echo "nodejs"
    elif [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
        echo "python"
    elif [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        echo "java"
    elif [ -f "go.mod" ]; then
        echo "golang"
    elif [ -f "composer.json" ]; then
        echo "php"
    elif [ -f "Cargo.toml" ]; then
        echo "rust"
    elif [ -f "Gemfile" ]; then
        echo "ruby"
    elif [ -f "Dockerfile" ]; then
        echo "docker"
    else
        echo "unknown"
    fi
}

# 获取版本信息
get_version() {
    if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
        git describe --tags --always 2>/dev/null || echo "latest"
    else
        echo "latest"
    fi
}

# 构建项目
build_project() {
    local project_type=$1

    log INFO "开始构建项目 (类型: ${project_type})"

    case ${project_type} in
        nodejs)
            build_nodejs
            ;;
        python)
            build_python
            ;;
        java)
            build_java
            ;;
        golang)
            build_golang
            ;;
        php)
            build_php
            ;;
        rust)
            build_rust
            ;;
        ruby)
            build_ruby
            ;;
        docker)
            log INFO "Docker 项目，跳过构建"
            ;;
        *)
            log WARN "未知项目类型，跳过构建"
            ;;
    esac

    log INFO "项目构建完成"
}

# Node.js 构建
build_nodejs() {
    log INFO "构建 Node.js 项目..."

    if [ -f "yarn.lock" ]; then
        yarn install --frozen-lockfile
        yarn build
    elif [ -f "pnpm-lock.yaml" ]; then
        pnpm install --frozen-lockfile
        pnpm build
    else
        npm ci
        npm run build
    fi
}

# Python 构建
build_python() {
    log INFO "构建 Python 项目..."

    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    elif [ -f "pyproject.toml" ]; then
        pip install .
    fi
}

# Java 构建
build_java() {
    log INFO "构建 Java 项目..."

    if [ -f "pom.xml" ]; then
        mvn clean package -DskipTests
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        ./gradlew clean build -x test
    fi
}

# Go 构建
build_golang() {
    log INFO "构建 Go 项目..."

    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=amd64

    go build -ldflags="-w -s" -o app ./cmd/app
}

# ============================================
# 测试框架
# ============================================

# 运行测试
run_tests() {
    local project_type=$1

    log INFO "开始运行测试..."

    case ${project_type} in
        nodejs)
            npm test
            ;;
        python)
            pytest || python -m unittest
            ;;
        java)
            mvn test
            ;;
        golang)
            go test ./...
            ;;
        *)
            log WARN "跳过测试"
            ;;
    esac

    if [ $? -eq 0 ]; then
        log INFO "测试通过"
        return 0
    else
        log ERROR "测试失败"
        return 1
    fi
}

# ============================================
# 部署策略
# ============================================

# 直接部署
deploy_direct() {
    local host=$1
    local user=$2
    local password=$3
    local deploy_path=$4
    local version=$5

    log INFO "执行直接部署到 ${host}..."

    # 备份当前版本
    backup_current_version "${host}" "${user}" "${password}" "${deploy_path}"

    # 打包项目
    local package_name="deploy-${version}.tar.gz"
    tar -czf "/tmp/${package_name}" \
        --exclude=node_modules \
        --exclude=.git \
        --exclude=*.log \
        --exclude=.env \
        .

    # 上传代码
    scp_upload "${host}" "${user}" "${password}" "/tmp/${package_name}" "/tmp/"

    # 部署代码
    ssh_connect "${host}" "${user}" "${password}" "
        # 创建版本目录
        mkdir -p ${deploy_path}/releases/${version}
        cd ${deploy_path}/releases/${version}

        # 解压代码
        tar -xzf /tmp/${package_name}

        # 安装生产依赖
        if [ -f 'package.json' ]; then
            npm ci --production
        fi

        # 更新软链接
        ln -sfn ${deploy_path}/releases/${version} ${deploy_path}/current

        # 清理旧版本（保留最近5个）
        cd ${deploy_path}/releases
        ls -dt */ | tail -n +6 | xargs rm -rf

        # 重启服务
        if command -v pm2 &> /dev/null; then
            cd ${deploy_path}/current
            pm2 restart ecosystem.config.js --env production
        elif command -v systemctl &> /dev/null; then
            systemctl restart app
        fi

        # 清理临时文件
        rm -f /tmp/${package_name}
    "

    # 清理本地临时文件
    rm -f "/tmp/${package_name}"

    log INFO "直接部署完成"
}

# Docker 部署
deploy_docker() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=$5

    log INFO "执行 Docker 部署到 ${host}..."

    # 构建镜像
    docker build -t "${image_name}:${version}" .
    docker tag "${image_name}:${version}" "${image_name}:latest"

    # 保存镜像
    docker save "${image_name}:${version}" | gzip > /tmp/app-image.tar.gz

    # 上传镜像
    scp_upload "${host}" "${user}" "${password}" "/tmp/app-image.tar.gz" "/tmp/"

    # 部署容器
    ssh_connect "${host}" "${user}" "${password}" "
        # 加载镜像
        docker load < /tmp/app-image.tar.gz

        # 停止旧容器
        docker stop ${image_name} 2>/dev/null || true
        docker rm ${image_name} 2>/dev/null || true

        # 启动新容器
        docker run -d \
            --name ${image_name} \
            --restart unless-stopped \
            -p 80:80 \
            -p 443:443 \
            -v /data/${image_name}:/app/data \
            -v /var/log/${image_name}:/app/logs \
            -e APP_ENV=production \
            -e LOG_LEVEL=info \
            --memory=4g \
            --cpus=2 \
            ${image_name}:${version}

        # 等待容器启动
        sleep 5

        # 检查容器状态
        if ! docker ps | grep -q ${image_name}; then
            echo '容器启动失败'
            docker logs ${image_name}
            exit 1
        fi

        # 清理临时文件
        rm -f /tmp/app-image.tar.gz
    "

    # 清理本地临时文件
    rm -f /tmp/app-image.tar.gz

    log INFO "Docker 部署完成"
}

# 蓝绿部署
deploy_blue_green() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=$5

    log INFO "执行蓝绿部署..."

    # 获取当前活跃环境
    local current_env=$(ssh_connect "${host}" "${user}" "${password}" "
        docker ps --format '{{.Names}}' | grep -E '^(blue|green)$' | head -1
    " || echo "")

    # 确定新环境
    if [ "${current_env}" = "blue" ]; then
        local new_env="green"
        local new_port=8081
    else
        local new_env="blue"
        local new_port=8080
    fi

    log INFO "当前环境: ${current_env:-无}, 部署新版本到: ${new_env}"

    # 构建镜像
    docker build -t "${image_name}:${version}" .

    # 保存镜像
    docker save "${image_name}:${version}" | gzip > /tmp/app-image.tar.gz

    # 上传镜像
    scp_upload "${host}" "${user}" "${password}" "/tmp/app-image.tar.gz" "/tmp/"

    # 部署新版本
    ssh_connect "${host}" "${user}" "${password}" "
        # 加载镜像
        docker load < /tmp/app-image.tar.gz

        # 停止新环境
        docker stop ${new_env} 2>/dev/null || true
        docker rm ${new_env} 2>/dev/null || true

        # 启动新版本
        docker run -d \
            --name ${new_env} \
            --restart unless-stopped \
            -p ${new_port}:80 \
            ${image_name}:${version}

        # 清理临时文件
        rm -f /tmp/app-image.tar.gz
    "

    # 清理本地临时文件
    rm -f /tmp/app-image.tar.gz

    # 健康检查
    if ! health_check "${host}" "${new_port}" "/health" 30; then
        log ERROR "新版本健康检查失败，回滚"

        ssh_connect "${host}" "${user}" "${password}" "
            docker stop ${new_env} 2>/dev/null || true
            docker rm ${new_env} 2>/dev/null || true
        "

        return 1
    fi

    # 切换流量
    ssh_connect "${host}" "${user}" "${password}" "
        # 更新 Nginx 配置
        if [ -f /etc/nginx/conf.d/app.conf ]; then
            sed -i 's/localhost:[0-9]*/localhost:${new_port}/' /etc/nginx/conf.d/app.conf
            nginx -s reload
        fi

        # 停止旧环境
        docker stop ${current_env} 2>/dev/null || true
    "

    log INFO "蓝绿部署完成"
}

# 健康检查
health_check() {
    local host=$1
    local port=$2
    local url=$3
    local timeout=$4

    log INFO "执行健康检查: http://${host}:${port}${url}"

    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while [ $(date +%s) -lt ${end_time} ]; do
        if curl -sf "http://${host}:${port}${url}" > /dev/null 2>&1; then
            log INFO "健康检查通过"
            return 0
        fi

        log DEBUG "等待服务启动..."
        sleep 2
    done

    log ERROR "健康检查超时"
    return 1
}

# ============================================
# 回滚机制
# ============================================

# 回滚到上一版本
rollback() {
    local host=$1
    local user=$2
    local password=$3
    local deploy_path=$4
    local version=${5:-""}

    log INFO "开始回滚..."

    if [ -z "${version}" ]; then
        # 获取上一版本
        version=$(ssh_connect "${host}" "${user}" "${password}" "
            cd ${deploy_path}/releases
            ls -dt */ | sed -n '2p' | tr -d '/'
        " || echo "")
    fi

    if [ -z "${version}" ]; then
        log ERROR "没有可回滚的版本"
        return 1
    fi

    log INFO "回滚到版本: ${version}"

    # 执行回滚
    ssh_connect "${host}" "${user}" "${password}" "
        # 检查版本是否存在
        if [ ! -d '${deploy_path}/releases/${version}' ]; then
            echo '版本不存在: ${version}'
            exit 1
        fi

        # 更新软链接
        ln -sfn ${deploy_path}/releases/${version} ${deploy_path}/current

        # 重启服务
        if command -v pm2 &> /dev/null; then
            cd ${deploy_path}/current
            pm2 restart ecosystem.config.js --env production
        elif command -v systemctl &> /dev/null; then
            systemctl restart app
        fi
    "

    # 发送回滚通知
    send_notification "rollback" "部署回滚" "已回滚到版本: ${version}"

    log INFO "回滚完成"
}

# ============================================
# 备份管理
# ============================================

# 备份当前版本
backup_current_version() {
    local host=$1
    local user=$2
    local password=$3
    local deploy_path=$4

    log INFO "备份当前版本..."

    local backup_path="/opt/backups"
    local timestamp=$(date '+%Y%m%d%H%M%S')

    ssh_connect "${host}" "${user}" "${password}" "
        # 创建备份目录
        mkdir -p ${backup_path}

        # 备份当前版本
        if [ -d '${deploy_path}/current' ]; then
            tar -czf ${backup_path}/backup-${timestamp}.tar.gz -C ${deploy_path} current

            # 清理旧备份（保留最近7个）
            cd ${backup_path}
            ls -t backup-*.tar.gz | tail -n +8 | xargs rm -f
        fi
    "

    log INFO "备份完成"
}

# ============================================
# 通知系统
# ============================================

# 发送通知
send_notification() {
    local status=$1
    local title=$2
    local content=$3

    # 发送邮件通知
    send_email_notification "${status}" "${title}" "${content}"

    # 发送钉钉通知
    send_dingtalk_notification "${status}" "${title}" "${content}"

    # 发送 Slack 通知
    send_slack_notification "${status}" "${title}" "${content}"
}

# 邮件通知
send_email_notification() {
    local status=$1
    local title=$2
    local content=$3

    local enabled=$(get_config ".notifications.email.enabled" "false")

    if [ "${enabled}" != "true" ]; then
        return 0
    fi

    log INFO "发送邮件通知..."

    local smtp_host=$(get_config ".notifications.email.smtp.host" "")
    local smtp_port=$(get_config ".notifications.email.smtp.port" "587")
    local smtp_user=$(replace_env_vars "$(get_config ".notifications.email.smtp.auth.user" "")")
    local smtp_pass=$(replace_env_vars "$(get_config ".notifications.email.smtp.auth.password" "")")
    local from=$(get_config ".notifications.email.from" "")
    local recipients=$(get_config ".notifications.email.recipients[]" "")

    # 构建邮件内容
    local subject="[${status}] ${title}"
    local body="部署通知\n\n状态: ${status}\n标题: ${title}\n内容: ${content}\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n版本: $(get_version)"

    # 发送邮件
    for recipient in ${recipients}; do
        echo -e "${body}" | mail -s "${subject}" \
            -S smtp="smtp://${smtp_host}:${smtp_port}" \
            -S smtp-auth=login \
            -S smtp-auth-user="${smtp_user}" \
            -S smtp-auth-password="${smtp_pass}" \
            -S from="${from}" \
            "${recipient}" 2>/dev/null || true
    done

    log INFO "邮件通知已发送"
}

# 钉钉通知
send_dingtalk_notification() {
    local status=$1
    local title=$2
    local content=$3

    local enabled=$(get_config ".notifications.dingtalk.enabled" "false")

    if [ "${enabled}" != "true" ]; then
        return 0
    fi

    log INFO "发送钉钉通知..."

    local webhook=$(replace_env_vars "$(get_config ".notifications.dingtalk.webhook" "")")

    local status_icon="✅"
    if [ "${status}" = "failure" ]; then
        status_icon="❌"
    elif [ "${status}" = "rollback" ]; then
        status_icon="⚠️"
    fi

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msgtype\": \"markdown\",
            \"markdown\": {
                \"title\": \"${status_icon} ${title}\",
                \"text\": \"${status_icon} **${title}**\n\n${content}\n\n---\n**时间**: $(date '+%Y-%m-%d %H:%M:%S')\n**版本**: $(get_version)\"
            }
        }" 2>/dev/null || true

    log INFO "钉钉通知已发送"
}

# Slack 通知
send_slack_notification() {
    local status=$1
    local title=$2
    local content=$3

    local enabled=$(get_config ".notifications.slack.enabled" "false")

    if [ "${enabled}" != "true" ]; then
        return 0
    fi

    log INFO "发送 Slack 通知..."

    local webhook=$(replace_env_vars "$(get_config ".notifications.slack.webhook" "")")
    local channel=$(get_config ".notifications.slack.channel" "#deployments")

    local status_icon="✅"
    local color="#4CAF50"

    if [ "${status}" = "failure" ]; then
        status_icon="❌"
        color="#F44336"
    elif [ "${status}" = "rollback" ]; then
        status_icon="⚠️"
        color="#FF9800"
    fi

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"channel\": \"${channel}\",
            \"attachments\": [
                {
                    \"color\": \"${color}\",
                    \"title\": \"${status_icon} ${title}\",
                    \"text\": \"${content}\",
                    \"footer\": \"$(date '+%Y-%m-%d %H:%M:%S') | $(get_version)\"
                }
            ]
        }" 2>/dev/null || true

    log INFO "Slack 通知已发送"
}

# ============================================
# 主部署流程
# ============================================

# 主部署函数
main_deploy() {
    local host=$1
    local user=$2
    local password=$3
    local env=$4
    local method=$5
    local strategy=$6
    local skip_test=$7
    local force=$8

    local start_time=$(date +%s)
    local version=$(get_version)
    local project_name=$(basename "$(pwd)")

    log INFO "=========================================="
    log INFO "开始部署 ${project_name} (${version})"
    log INFO "环境: ${env}"
    log INFO "方式: ${method}"
    log INFO "策略: ${strategy}"
    log INFO "=========================================="

    # 审计日志
    audit_log "deploy_start" "$(whoami)" "env=${env}, version=${version}"

    # 检测项目类型
    local project_type=$(detect_project_type)
    log INFO "项目类型: ${project_type}"

    # 构建项目
    build_project "${project_type}"

    # 运行测试
    if [ "${skip_test}" != "true" ]; then
        if ! run_tests "${project_type}"; then
            log ERROR "测试失败"
            send_notification "failure" "部署失败 - ${project_name}" "测试未通过"
            audit_log "deploy_failed" "$(whoami)" "reason=test_failed"
            exit 1
        fi
    fi

    # 执行部署
    case ${strategy} in
        direct)
            deploy_direct "${host}" "${user}" "${password}" "/var/www/app" "${version}"
            ;;
        rolling)
            deploy_direct "${host}" "${user}" "${password}" "/var/www/app" "${version}"
            ;;
        blue-green)
            deploy_blue_green "${host}" "${user}" "${password}" "${project_name}" "${version}"
            ;;
        canary)
            log WARN "金丝雀部署暂未实现，使用蓝绿部署代替"
            deploy_blue_green "${host}" "${user}" "${password}" "${project_name}" "${version}"
            ;;
        *)
            log ERROR "不支持的部署策略: ${strategy}"
            exit 1
            ;;
    esac

    # 健康检查
    if [ "${force}" != "true" ]; then
        if ! health_check "${host}" "80" "/health" 30; then
            log ERROR "健康检查失败"

            # 自动回滚
            log INFO "开始自动回滚..."
            rollback "${host}" "${user}" "${password}" "/var/www/app"

            send_notification "failure" "部署失败 - ${project_name}" "健康检查未通过，已自动回滚"
            audit_log "deploy_failed" "$(whoami)" "reason=health_check_failed"
            exit 1
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 发送成功通知
    local notify_content="**项目**: ${project_name}\n**版本**: ${version}\n**环境**: ${env}\n**服务器**: ${host}\n**耗时**: ${duration}秒\n**状态**: 部署成功"

    send_notification "success" "部署成功 - ${project_name}" "${notify_content}"
    audit_log "deploy_success" "$(whoami)" "version=${version}, duration=${duration}s"

    log INFO "=========================================="
    log INFO "部署完成！耗时 ${duration} 秒"
    log INFO "=========================================="
}

# ============================================
# 命令行接口
# ============================================

# 显示帮助
show_help() {
    cat << EOF
Cloud Deploy - 企业级多云部署平台 v${VERSION}

用法: deploy [命令] [选项]

命令:
  init                    初始化配置
  deploy                  执行部署
  rollback                回滚到上一版本
  status                  查看部署状态
  history                 查看部署历史
  logs                    查看日志
  config                  管理配置

选项:
  --env ENV               部署环境 (production/staging/development)
  --method METHOD         部署方式 (direct/docker/kubernetes)
  --strategy STRATEGY     部署策略 (direct/rolling/blue-green/canary)
  --host HOST             服务器地址
  --user USER             登录用户
  --password PASSWORD     登录密码
  --version VERSION       指定版本
  --skip-test             跳过测试
  --force                 强制部署
  --help                  显示帮助

示例:
  deploy init --wizard
  deploy --env production
  deploy --env staging --method docker
  deploy --strategy blue-green
  deploy --rollback --version v1.2.0
  deploy --status
  deploy --history
  deploy --logs --follow

环境变量:
  DEPLOY_CONFIG           配置文件路径
  SERVER_PASSWORD         服务器密码
  DOCKER_USER             Docker 仓库用户名
  DOCKER_PASSWORD         Docker 仓库密码
  SMTP_PASSWORD           邮件密码
  DINGTALK_WEBHOOK        钉钉 Webhook
  SLACK_WEBHOOK           Slack Webhook
EOF
}

# 解析命令行参数
parse_args() {
    COMMAND=""
    ENV="production"
    METHOD="direct"
    STRATEGY="direct"
    HOST=""
    USER=""
    PASSWORD=""
    VERSION=""
    SKIP_TEST=false
    FORCE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            init|deploy|rollback|status|history|logs|config)
                COMMAND="$1"
                shift
                ;;
            --env)
                ENV="$2"
                shift 2
                ;;
            --method)
                METHOD="$2"
                shift 2
                ;;
            --strategy)
                STRATEGY="$2"
                shift 2
                ;;
            --host)
                HOST="$2"
                shift 2
                ;;
            --user)
                USER="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --skip-test)
                SKIP_TEST=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log ERROR "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 交互式输入
interactive_input() {
    if [ -z "${HOST}" ]; then
        read -p "请输入服务器 IP: " HOST
    fi

    if [ -z "${USER}" ]; then
        read -p "请输入用户名 [root]: " USER
        USER=${USER:-root}
    fi

    if [ -z "${PASSWORD}" ]; then
        read -s -p "请输入密码: " PASSWORD
        echo
    fi

    if [ "${METHOD}" = "direct" ]; then
        echo "选择部署方式:"
        echo "1) 直接部署"
        echo "2) Docker 部署"
        read -p "请选择 [1]: " method_choice

        case ${method_choice} in
            2) METHOD="docker" ;;
            *) METHOD="direct" ;;
        esac
    fi

    if [ "${STRATEGY}" = "direct" ]; then
        echo "选择部署策略:"
        echo "1) 直接部署"
        echo "2) 蓝绿部署"
        read -p "请选择 [1]: " strategy_choice

        case ${strategy_choice} in
            2) STRATEGY="blue-green" ;;
            *) STRATEGY="direct" ;;
        esac
    fi
}

# 主函数
main() {
    # 检查锁
    if [ -f "${LOCK_FILE}" ]; then
        log ERROR "部署正在进行中，请稍后再试"
        exit 1
    fi

    # 创建锁
    echo $$ > "${LOCK_FILE}"

    # 加载配置
    load_config

    # 解析参数
    parse_args "$@"

    # 执行命令
    case ${COMMAND} in
        init)
            log INFO "初始化配置..."
            mkdir -p ~/.deploy-tools
            log INFO "配置目录已创建: ~/.deploy-tools"
            ;;
        deploy|"")
            interactive_input
            main_deploy "${HOST}" "${USER}" "${PASSWORD}" "${ENV}" "${METHOD}" "${STRATEGY}" "${SKIP_TEST}" "${FORCE}"
            ;;
        rollback)
            if [ -z "${HOST}" ]; then
                read -p "请输入服务器 IP: " HOST
            fi
            if [ -z "${USER}" ]; then
                read -p "请输入用户名 [root]: " USER
                USER=${USER:-root}
            fi
            if [ -z "${PASSWORD}" ]; then
                read -s -p "请输入密码: " PASSWORD
                echo
            fi
            rollback "${HOST}" "${USER}" "${PASSWORD}" "/var/www/app" "${VERSION}"
            ;;
        status)
            log INFO "查看部署状态..."
            ;;
        history)
            log INFO "查看部署历史..."
            ;;
        logs)
            log INFO "查看日志..."
            ;;
        config)
            log INFO "管理配置..."
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
