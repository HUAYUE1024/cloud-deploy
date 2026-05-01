#!/bin/bash
#
# Cloud Deploy 安装脚本
# 版本: 3.0.0
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

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
                lsb-release
            ;;
        redhat)
            sudo yum install -y \
                curl \
                wget \
                git \
                jq \
                sshpass \
                mailx \
                ca-certificates
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
            ;;
    esac

    log_info "依赖安装完成"
}

# 安装 yq
install_yq() {
    log_step "安装 yq..."

    if command -v yq &> /dev/null; then
        log_info "yq 已安装"
        return 0
    fi

    local os=$(detect_os)

    case $os in
        linux|debian|redhat)
            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            sudo chmod +x /usr/local/bin/yq
            ;;
        macos)
            brew install yq
            ;;
    esac

    log_info "yq 安装完成"
}

# 安装 Docker
install_docker() {
    log_step "检查 Docker..."

    if command -v docker &> /dev/null; then
        log_info "Docker 已安装"
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
            ;;
        macos)
            log_warn "请手动安装 Docker Desktop for Mac"
            log_info "下载地址: https://www.docker.com/products/docker-desktop"
            ;;
    esac

    log_info "Docker 安装完成"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."

    # 创建配置目录
    mkdir -p ~/.deploy-tools

    # 创建日志目录
    sudo mkdir -p /var/log/deploy
    sudo chmod 755 /var/log/deploy

    # 创建备份目录
    sudo mkdir -p /opt/backups
    sudo chmod 755 /opt/backups

    log_info "目录创建完成"
}

# 安装部署工具
install_deploy_tool() {
    log_step "安装部署工具..."

    # 获取脚本所在目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parent_dir="$(dirname "$script_dir")"

    # 复制主脚本
    sudo cp "${parent_dir}/src/deploy.sh" /usr/local/bin/deploy
    sudo chmod +x /usr/local/bin/deploy

    # 复制配置示例
    if [ ! -f ~/.deploy-tools/config.yaml ]; then
        cp "${parent_dir}/config/config.example.yaml" ~/.deploy-tools/config.yaml
        log_info "配置文件已创建: ~/.deploy-tools/config.yaml"
    fi

    log_info "部署工具安装完成"
}

# 配置环境变量
setup_environment() {
    log_step "配置环境变量..."

    # 检查是否已配置
    if grep -q "DEPLOY_CONFIG" ~/.bashrc 2>/dev/null; then
        log_info "环境变量已配置"
        return 0
    fi

    # 添加环境变量
    cat >> ~/.bashrc << 'EOF'

# Cloud Deploy 环境变量
export DEPLOY_CONFIG="$HOME/.deploy-tools/config.yaml"
export PATH="/usr/local/bin:$PATH"
EOF

    # 重新加载环境变量
    source ~/.bashrc

    log_info "环境变量配置完成"
}

# 验证安装
verify_installation() {
    log_step "验证安装..."

    local errors=0

    # 检查 deploy 命令
    if ! command -v deploy &> /dev/null; then
        log_error "deploy 命令未找到"
        errors=$((errors + 1))
    fi

    # 检查配置文件
    if [ ! -f ~/.deploy-tools/config.yaml ]; then
        log_error "配置文件未找到"
        errors=$((errors + 1))
    fi

    # 检查依赖
    local deps=("curl" "git" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            log_error "$dep 未安装"
            errors=$((errors + 1))
        fi
    done

    if [ $errors -eq 0 ]; then
        log_info "安装验证通过"
        return 0
    else
        log_error "安装验证失败，发现 ${errors} 个错误"
        return 1
    fi
}

# 显示安装完成信息
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
    echo -e "  ${BLUE}deploy init${NC}                    # 初始化配置"
    echo -e "  ${BLUE}deploy --help${NC}                  # 查看帮助"
    echo -e "  ${BLUE}deploy --env production${NC}        # 部署到生产环境"
    echo ""
    echo -e "更多信息请查看文档: ${BLUE}https://github.com/HUAYUE1024/cloud-deploy${NC}"
    echo ""
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "  ____ _                 _ ____             _           "
    echo " / ___| | ___  _   _  __| |  _ \  ___   ___| | _____ _ __ "
    echo "| |   | |/ _ \| | | |/ _\` | | | |/ _ \ / __| |/ / _ \ '__|"
    echo "| |___| | (_) | |_| | (_| | |_| | (_) | (__|   <  __/ |   "
    echo " \____|_|\___/ \__,_|\__,_|____/ \___/ \___|_|\_\___|_|   "
    echo ""
    echo " 企业级多云部署平台 v3.0.0"
    echo -e "${NC}"
    echo ""

    # 检测操作系统
    local os=$(detect_os)
    log_info "检测到操作系统: ${os}"

    # 安装依赖
    install_dependencies "$os"

    # 安装 yq
    install_yq

    # 安装 Docker
    install_docker

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
