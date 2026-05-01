#!/bin/bash
#
# Cloud Deploy 安装脚本
# 版本: 3.1.0
#

set -e

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================
# 日志函数
# ============================================
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

# ============================================
# 系统检测
# ============================================

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        elif [ -f /etc/alpine-release ]; then
            echo "alpine"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# 检测架构
detect_arch() {
    local arch=$(uname -m)
    case ${arch} in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo "${arch}" ;;
    esac
}

# 检测包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v brew &> /dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# ============================================
# 依赖安装
# ============================================

# 安装依赖
install_dependencies() {
    local os=$1

    log_step "安装系统依赖..."

    case $os in
        debian)
            sudo apt-get update
            sudo apt-get install -y \
                curl \
                wget \
                git \
                jq \
                sshpass \
                mailutils \
                ca-certificates \
                gnupg \
                lsb-release \
                bc
            ;;
        redhat)
            sudo yum install -y \
                curl \
                wget \
                git \
                jq \
                sshpass \
                mailx \
                ca-certificates \
                bc
            ;;
        alpine)
            sudo apk add --no-cache \
                curl \
                wget \
                git \
                jq \
                openssh-client \
                mailx \
                ca-certificates \
                bc
            ;;
        macos)
            if ! command -v brew &> /dev/null; then
                log_error "请先安装 Homebrew: https://brew.sh"
                exit 1
            fi

            brew install \
                curl \
                wget \
                git \
                jq \
                sshpass \
                mailutils
            ;;
        *)
            log_warn "未知操作系统，请手动安装依赖"
            log_warn "必需依赖: curl, wget, git, jq, sshpass"
            ;;
    esac

    log_success "依赖安装完成"
}

# ============================================
# 工具安装
# ============================================

# 安装 yq
install_yq() {
    log_step "安装 yq..."

    if command -v yq &> /dev/null; then
        log_success "yq 已安装: $(yq --version)"
        return 0
    fi

    local os=$(detect_os)
    local arch=$(detect_arch)

    case $os in
        linux|debian|redhat|alpine)
            local yq_arch="amd64"
            [ "${arch}" = "arm64" ] && yq_arch="arm64"

            sudo wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}"
            sudo chmod +x /usr/local/bin/yq
            ;;
        macos)
            brew install yq
            ;;
    esac

    if command -v yq &> /dev/null; then
        log_success "yq 安装完成"
    else
        log_warn "yq 安装失败，部分功能可能不可用"
    fi
}

# 安装 Docker
install_docker() {
    log_step "检查 Docker..."

    if command -v docker &> /dev/null; then
        log_success "Docker 已安装: $(docker --version)"
        return 0
    fi

    log_warn "Docker 未安装"
    read -p "是否安装 Docker? (y/n) [y]: " install_choice
    install_choice=${install_choice:-y}

    if [ "$install_choice" != "y" ]; then
        log_warn "跳过 Docker 安装"
        return 0
    fi

    local os=$(detect_os)

    case $os in
        linux|debian|redhat)
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            log_warn "请重新登录以使 Docker 组生效"
            ;;
        alpine)
            sudo apk add --no-cache docker docker-compose
            sudo rc-update add docker boot
            sudo service docker start
            ;;
        macos)
            log_warn "请手动安装 Docker Desktop for Mac"
            log_info "下载地址: https://www.docker.com/products/docker-desktop"
            ;;
    esac

    if command -v docker &> /dev/null; then
        log_success "Docker 安装完成"
    else
        log_warn "Docker 安装可能需要重新登录后生效"
    fi
}

# 安装 Docker Compose
install_docker_compose() {
    log_step "检查 Docker Compose..."

    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
        log_success "Docker Compose 已安装"
        return 0
    fi

    log_warn "Docker Compose 未安装"
    read -p "是否安装 Docker Compose? (y/n) [y]: " install_choice
    install_choice=${install_choice:-y}

    if [ "$install_choice" != "y" ]; then
        log_warn "跳过 Docker Compose 安装"
        return 0
    fi

    local os=$(detect_os)
    local arch=$(detect_arch)

    case $os in
        linux|debian|redhat)
            local compose_arch="x86_64"
            [ "${arch}" = "arm64" ] && compose_arch="aarch64"

            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${compose_arch}" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            ;;
        macos)
            log_info "Docker Compose 已包含在 Docker Desktop 中"
            ;;
    esac

    if command -v docker-compose &> /dev/null; then
        log_success "Docker Compose 安装完成"
    else
        log_warn "Docker Compose 安装失败"
    fi
}

# ============================================
# 目录和配置
# ============================================

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."

    # 创建配置目录
    mkdir -p ~/.deploy-tools

    # 创建日志目录
    if [ -w /var/log ] || [ "$(id -u)" -eq 0 ]; then
        sudo mkdir -p /var/log/deploy
        sudo chmod 755 /var/log/deploy
    else
        mkdir -p ~/.deploy-tools/logs
        log_warn "无法创建 /var/log/deploy，使用 ~/.deploy-tools/logs"
    fi

    # 创建备份目录
    if [ -w /opt ] || [ "$(id -u)" -eq 0 ]; then
        sudo mkdir -p /opt/backups
        sudo chmod 755 /opt/backups
    else
        mkdir -p ~/.deploy-tools/backups
        log_warn "无法创建 /opt/backups，使用 ~/.deploy-tools/backups"
    fi

    log_success "目录创建完成"
}

# 安装部署工具
install_deploy_tool() {
    log_step "安装部署工具..."

    # 获取脚本所在目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parent_dir="$(dirname "$script_dir")"

    # 检查源文件
    if [ ! -f "${parent_dir}/src/deploy.sh" ]; then
        log_error "部署脚本未找到: ${parent_dir}/src/deploy.sh"
        return 1
    fi

    # 安装主脚本和模块
    local install_dir="/usr/local/lib/cloud-deploy"
    sudo mkdir -p "${install_dir}"

    # 复制模块文件
    sudo cp "${parent_dir}/src/deploy.sh" "${install_dir}/"
    sudo cp "${parent_dir}/src/utils.sh" "${install_dir}/" 2>/dev/null || true
    sudo cp "${parent_dir}/src/docker.sh" "${install_dir}/" 2>/dev/null || true
    sudo cp "${parent_dir}/src/notifications.sh" "${install_dir}/" 2>/dev/null || true
    sudo cp "${parent_dir}/src/monitoring.sh" "${install_dir}/" 2>/dev/null || true

    sudo chmod +x "${install_dir}/deploy.sh"

    # 创建命令链接
    sudo ln -sf "${install_dir}/deploy.sh" /usr/local/bin/deploy

    # 复制配置示例
    if [ ! -f ~/.deploy-tools/config.yaml ]; then
        cp "${parent_dir}/config/config.example.yaml" ~/.deploy-tools/config.yaml
        log_success "配置文件已创建: ~/.deploy-tools/config.yaml"
    else
        log_info "配置文件已存在，跳过"
    fi

    log_success "部署工具安装完成"
}

# ============================================
# 环境配置
# ============================================

# 配置环境变量
setup_environment() {
    log_step "配置环境变量..."

    # 检测 shell 配置文件
    local shell_rc=""
    if [ -f ~/.bashrc ]; then
        shell_rc=~/.bashrc
    elif [ -f ~/.zshrc ]; then
        shell_rc=~/.zshrc
    elif [ -f ~/.profile ]; then
        shell_rc=~/.profile
    fi

    if [ -z "${shell_rc}" ]; then
        log_warn "未找到 shell 配置文件，跳过环境变量配置"
        return 0
    fi

    # 检查是否已配置
    if grep -q "DEPLOY_CONFIG" "${shell_rc}" 2>/dev/null; then
        log_success "环境变量已配置"
        return 0
    fi

    # 添加环境变量
    cat >> "${shell_rc}" << 'EOF'

# Cloud Deploy 环境变量
export DEPLOY_CONFIG="$HOME/.deploy-tools/config.yaml"
export PATH="/usr/local/bin:$PATH"
EOF

    # 重新加载环境变量
    source "${shell_rc}" 2>/dev/null || true

    log_success "环境变量配置完成"
}

# ============================================
# 验证安装
# ============================================

# 验证安装
verify_installation() {
    log_step "验证安装..."

    local errors=0
    local warnings=0

    # 检查 deploy 命令
    if command -v deploy &> /dev/null; then
        log_success "deploy 命令: $(deploy --version 2>/dev/null || echo '已安装')"
    else
        log_error "deploy 命令未找到"
        errors=$((errors + 1))
    fi

    # 检查配置文件
    if [ -f ~/.deploy-tools/config.yaml ]; then
        log_success "配置文件: ~/.deploy-tools/config.yaml"
    else
        log_error "配置文件未找到"
        errors=$((errors + 1))
    fi

    # 检查核心依赖
    local core_deps=("curl" "git" "jq")
    for dep in "${core_deps[@]}"; do
        if command -v $dep &> /dev/null; then
            log_success "$dep: $(command -v $dep)"
        else
            log_error "$dep 未安装"
            errors=$((errors + 1))
        fi
    done

    # 检查可选依赖
    local optional_deps=("sshpass" "yq" "docker")
    for dep in "${optional_deps[@]}"; do
        if command -v $dep &> /dev/null; then
            log_success "$dep: $(command -v $dep)"
        else
            log_warn "$dep 未安装（可选）"
            warnings=$((warnings + 1))
        fi
    done

    echo ""

    if [ $errors -eq 0 ]; then
        log_success "安装验证通过"
        [ $warnings -gt 0 ] && log_warn "有 ${warnings} 个可选依赖未安装"
        return 0
    else
        log_error "安装验证失败，发现 ${errors} 个错误"
        return 1
    fi
}

# ============================================
# 完成信息
# ============================================

show_completion() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Cloud Deploy 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "配置文件: ${BLUE}~/.deploy-tools/config.yaml${NC}"
    echo -e "日志目录: ${BLUE}/var/log/deploy${NC}"
    echo -e "备份目录: ${BLUE}/opt/backups${NC}"
    echo ""
    echo -e "使用方法:"
    echo -e "  ${BLUE}deploy --help${NC}                  # 查看帮助"
    echo -e "  ${BLUE}deploy --env production${NC}        # 部署到生产环境"
    echo -e "  ${BLUE}deploy --strategy blue-green${NC}   # 蓝绿部署"
    echo -e "  ${BLUE}deploy --method docker${NC}         # Docker 部署"
    echo -e "  ${BLUE}deploy --monitor${NC}               # 系统监控"
    echo -e "  ${BLUE}deploy --health <url>${NC}          # 健康检查"
    echo ""
    echo -e "快速开始:"
    echo -e "  1. 编辑配置文件: ${BLUE}vim ~/.deploy-tools/config.yaml${NC}"
    echo -e "  2. 测试连接: ${BLUE}deploy --host <IP> --user root --password <密码> --env staging${NC}"
    echo ""
    echo -e "更多信息: ${BLUE}https://github.com/HUAYUE1024/cloud-deploy${NC}"
    echo ""
}

# ============================================
# 主函数
# ============================================

main() {
    echo -e "${CYAN}"
    echo "  ____ _                 _ ____             _           "
    echo " / ___| | ___  _   _  __| |  _ \  ___   ___| | _____ _ __ "
    echo "| |   | |/ _ \| | | |/ _\` | | | |/ _ \ / __| |/ / _ \ '__|"
    echo "| |___| | (_) | |_| | (_| | |_| | (_) | (__|   <  __/ |   "
    echo " \____|_|\___/ \__,_|\__,_|____/ \___/ \___|_|\_\___|_|   "
    echo ""
    echo " 企业级多云部署平台 v3.1.0"
    echo -e "${NC}"
    echo ""

    # 检测操作系统
    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "检测到系统: ${os} (${arch})"

    # 检查是否为 root
    if [ "$(id -u)" -eq 0 ]; then
        log_warn "以 root 用户运行，部分操作可能需要调整权限"
    fi

    # 安装依赖
    install_dependencies "$os"

    # 安装 yq
    install_yq

    # 安装 Docker
    install_docker

    # 安装 Docker Compose
    install_docker_compose

    # 创建目录
    create_directories

    # 安装部署工具
    install_deploy_tool

    # 配置环境变量
    setup_environment

    # 验证安装
    verify_installation

    # 显示完成信息
    show_completion
}

# 运行主函数
main "$@"
