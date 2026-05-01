#!/bin/bash
#
# Cloud Deploy - 企业级多云部署平台
# 版本: 3.1.0
# 作者: HUAYUE1024
# 仓库: https://github.com/HUAYUE1024/cloud-deploy
#

set -euo pipefail

# ============================================
# 配置和常量
# ============================================

readonly VERSION="3.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${DEPLOY_CONFIG:-$HOME/.deploy-tools/config.yaml}"
readonly LOG_DIR="/var/log/deploy"
readonly AUDIT_LOG="${LOG_DIR}/audit.log"
readonly LOCK_FILE="/tmp/deploy.lock"

# ============================================
# 加载模块化库
# ============================================

# 加载工具函数库
[ -f "${SCRIPT_DIR}/utils.sh" ] && source "${SCRIPT_DIR}/utils.sh"

# 加载 Docker 函数库
[ -f "${SCRIPT_DIR}/docker.sh" ] && source "${SCRIPT_DIR}/docker.sh"

# 加载通知函数库
[ -f "${SCRIPT_DIR}/notifications.sh" ] && source "${SCRIPT_DIR}/notifications.sh"

# 加载监控函数库
[ -f "${SCRIPT_DIR}/monitoring.sh" ] && source "${SCRIPT_DIR}/monitoring.sh"

# ============================================
# 错误处理和清理
# ============================================

# 错误处理
error_handler() {
    local line_no=$1
    local error_code=$2
    log_error "脚本执行失败，行号: ${line_no}, 错误码: ${error_code}"

    # 发送失败通知
    if type send_all_notifications &> /dev/null; then
        send_all_notifications "failure" "部署失败" "错误发生在第 ${line_no} 行，错误码: ${error_code}"
    fi

    # 清理资源
    cleanup

    exit ${error_code}
}

trap 'error_handler ${LINENO} $?' ERR

# 清理函数
cleanup() {
    log_info "执行清理操作..."

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

# ============================================
# 配置管理
# ============================================

# 加载配置
load_config() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        log_warn "配置文件不存在: ${CONFIG_FILE}，使用默认配置"
        CONFIG="{}"
        return 0
    fi

    # 检查 yq 是否安装
    if command -v yq &> /dev/null; then
        CONFIG=$(cat "${CONFIG_FILE}")
    else
        log_warn "yq 未安装，使用简化配置解析"
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

# SCP 下载函数
scp_download() {
    local host=$1
    local user=$2
    local password=$3
    local src=$4
    local dst=$5

    local scp_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -r"

    if command -v sshpass &> /dev/null; then
        sshpass -p "${password}" scp ${scp_opts} "${user}@${host}:${src}" "${dst}"
    else
        scp ${scp_opts} "${user}@${host}:${src}" "${dst}"
    fi
}

# ============================================
# 项目检测和构建
# ============================================

# 检测项目类型
detect_project_type() {
    log_info "检测项目类型..."

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

    log_info "开始构建项目 (类型: ${project_type})"

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
            log_info "Docker 项目，跳过构建"
            ;;
        *)
            log_warn "未知项目类型，跳过构建"
            ;;
    esac

    log_info "项目构建完成"
}

# Node.js 构建
build_nodejs() {
    log_info "构建 Node.js 项目..."

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
    log_info "构建 Python 项目..."

    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    elif [ -f "pyproject.toml" ]; then
        pip install .
    fi
}

# Java 构建
build_java() {
    log_info "构建 Java 项目..."

    if [ -f "pom.xml" ]; then
        mvn clean package -DskipTests
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        ./gradlew clean build -x test
    fi
}

# Go 构建
build_golang() {
    log_info "构建 Go 项目..."

    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=amd64

    go build -ldflags="-w -s" -o app ./cmd/app
}

# PHP 构建
build_php() {
    log_info "构建 PHP 项目..."

    if [ -f "composer.json" ]; then
        composer install --no-dev --optimize-autoloader
    fi
}

# Rust 构建
build_rust() {
    log_info "构建 Rust 项目..."

    cargo build --release
}

# Ruby 构建
build_ruby() {
    log_info "构建 Ruby 项目..."

    if [ -f "Gemfile" ]; then
        bundle install --without development test
    fi
}

# ============================================
# 测试框架
# ============================================

# 运行测试
run_tests() {
    local project_type=$1

    log_info "开始运行测试..."

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
        php)
            phpunit
            ;;
        rust)
            cargo test
            ;;
        ruby)
            bundle exec rspec
            ;;
        *)
            log_warn "跳过测试"
            return 0
            ;;
    esac

    if [ $? -eq 0 ]; then
        log_info "测试通过"
        return 0
    else
        log_error "测试失败"
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

    log_info "执行直接部署到 ${host}..."

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

    log_info "直接部署完成"
}

# Docker 部署
deploy_docker() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=$5

    log_info "执行 Docker 部署到 ${host}..."

    # 使用 Docker 函数库进行远程部署
    docker_remote_deploy "${host}" "${user}" "${password}" "${image_name}" "${version}"

    log_info "Docker 部署完成"
}

# 蓝绿部署
deploy_blue_green() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=$5

    log_info "执行蓝绿部署..."

    # 使用 Docker 函数库进行蓝绿部署
    docker_remote_blue_green "${host}" "${user}" "${password}" "${image_name}" "${version}"

    log_info "蓝绿部署完成"
}

# 金丝雀部署
deploy_canary() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=$5
    local canary_percent=${6:-10}

    log_info "执行金丝雀部署 (${canary_percent}% 流量)..."

    # 构建新版本
    docker_build "${image_name}" "${version}"
    local image_file=$(docker_save "${image_name}" "${version}")

    # 上传镜像
    scp_upload "${host}" "${user}" "${password}" "${image_file}" "/tmp/"

    # 部署金丝雀版本
    ssh_connect "${host}" "${user}" "${password}" "
        # 加载镜像
        docker load < /tmp/$(basename ${image_file})

        # 停止旧的金丝雀容器
        docker stop canary 2>/dev/null || true
        docker rm canary 2>/dev/null || true

        # 启动金丝雀容器
        docker run -d \
            --name canary \
            --restart unless-stopped \
            -p 8081:80 \
            ${image_name}:${version}

        # 配置 Nginx 金丝雀路由
        if [ -f /etc/nginx/conf.d/app.conf ]; then
            cat > /etc/nginx/conf.d/canary.conf << 'NGINX'
upstream backend {
    server localhost:80 weight=90;
    server localhost:8081 weight=10;
}
NGINX
            nginx -s reload
        fi

        rm -f /tmp/$(basename ${image_file})
    "

    rm -f "${image_file}"

    log_info "金丝雀部署完成"
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

    log_info "开始回滚..."

    if [ -z "${version}" ]; then
        # 获取上一版本
        version=$(ssh_connect "${host}" "${user}" "${password}" "
            cd ${deploy_path}/releases
            ls -dt */ | sed -n '2p' | tr -d '/'
        " || echo "")
    fi

    if [ -z "${version}" ]; then
        log_error "没有可回滚的版本"
        return 1
    fi

    log_info "回滚到版本: ${version}"

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
    if type notify_rollback &> /dev/null; then
        notify_rollback "$(basename $(pwd))" "$(get_version)" "${version}"
    fi

    log_info "回滚完成"
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

    log_info "备份当前版本..."

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

    log_info "备份完成"
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

    log_info "=========================================="
    log_info "开始部署 ${project_name} (${version})"
    log_info "环境: ${env}"
    log_info "方式: ${method}"
    log_info "策略: ${strategy}"
    log_info "=========================================="

    # 审计日志
    audit_log "deploy_start" "$(whoami)" "env=${env}, version=${version}"

    # 检测项目类型
    local project_type=$(detect_project_type)
    log_info "项目类型: ${project_type}"

    # 构建项目
    build_project "${project_type}"

    # 运行测试
    if [ "${skip_test}" != "true" ]; then
        if ! run_tests "${project_type}"; then
            log_error "测试失败"

            if type notify_deploy_failure &> /dev/null; then
                notify_deploy_failure "${project_name}" "测试未通过"
            fi

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
            deploy_canary "${host}" "${user}" "${password}" "${project_name}" "${version}"
            ;;
        *)
            log_error "不支持的部署策略: ${strategy}"
            exit 1
            ;;
    esac

    # 健康检查
    if [ "${force}" != "true" ]; then
        if type wait_for_healthy &> /dev/null; then
            if ! wait_for_healthy "tcp" "${host}:80" 30; then
                log_error "健康检查失败"

                # 自动回滚
                log_info "开始自动回滚..."
                rollback "${host}" "${user}" "${password}" "/var/www/app"

                if type notify_deploy_failure &> /dev/null; then
                    notify_deploy_failure "${project_name}" "健康检查未通过，已自动回滚"
                fi

                audit_log "deploy_failed" "$(whoami)" "reason=health_check_failed"
                exit 1
            fi
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 发送成功通知
    if type notify_deploy_success &> /dev/null; then
        notify_deploy_success "${project_name}" "${version}" "${env}" "${host}" "${duration}"
    fi

    audit_log "deploy_success" "$(whoami)" "version=${version}, duration=${duration}s"

    log_info "=========================================="
    log_info "部署完成！耗时 ${duration} 秒"
    log_info "=========================================="
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
  monitor                 系统监控
  health                  健康检查

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
  deploy --monitor
  deploy --health http://example.com

环境变量:
  DEPLOY_CONFIG           配置文件路径
  SERVER_PASSWORD         服务器密码
  DOCKER_USER             Docker 仓库用户名
  DOCKER_PASSWORD         Docker 仓库密码
  SMTP_PASSWORD           邮件密码
  DINGTALK_WEBHOOK        钉钉 Webhook
  SLACK_WEBHOOK           Slack Webhook
  WECHAT_WEBHOOK          企业微信 Webhook
  FEISHU_WEBHOOK          飞书 Webhook
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
    MONITOR_TARGET=""
    HEALTH_TARGET=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            init|deploy|rollback|status|history|logs|config|monitor|health)
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
            --monitor)
                COMMAND="monitor"
                shift
                ;;
            --health)
                COMMAND="health"
                HEALTH_TARGET="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
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
        echo "2) 滚动更新"
        echo "3) 蓝绿部署"
        echo "4) 金丝雀部署"
        read -p "请选择 [1]: " strategy_choice

        case ${strategy_choice} in
            2) STRATEGY="rolling" ;;
            3) STRATEGY="blue-green" ;;
            4) STRATEGY="canary" ;;
            *) STRATEGY="direct" ;;
        esac
    fi
}

# 主函数
main() {
    # 检查锁
    if [ -f "${LOCK_FILE}" ]; then
        log_error "部署正在进行中，请稍后再试"
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
            log_info "初始化配置..."
            mkdir -p ~/.deploy-tools
            log_info "配置目录已创建: ~/.deploy-tools"
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
            log_info "查看部署状态..."
            # TODO: 实现状态查看
            ;;
        history)
            log_info "查看部署历史..."
            # TODO: 实现历史查看
            ;;
        logs)
            log_info "查看日志..."
            # TODO: 实现日志查看
            ;;
        config)
            log_info "管理配置..."
            # TODO: 实现配置管理
            ;;
        monitor)
            log_info "系统监控..."
            if type get_system_snapshot &> /dev/null; then
                get_system_snapshot
            else
                log_error "监控模块未加载"
            fi
            ;;
        health)
            log_info "健康检查: ${HEALTH_TARGET}"
            if type health_check_http &> /dev/null; then
                if health_check_http "${HEALTH_TARGET}"; then
                    log_info "健康检查通过"
                else
                    log_error "健康检查失败"
                    exit 1
                fi
            else
                log_error "监控模块未加载"
            fi
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
