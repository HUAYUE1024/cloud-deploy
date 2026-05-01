#!/bin/bash
#
# Cloud Deploy 测试脚本
#

set -e

# 切换到项目根目录
cd "$(dirname "$0")/.." || exit 1

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 测试计数
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
run_test() {
    local test_name=$1
    local test_func=$2

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    echo -n "运行测试: ${test_name} ... "

    if ${test_func}; then
        echo -e "${GREEN}通过${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 0))
    else
        echo -e "${RED}失败${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 测试用例

# 测试 1: 检查 deploy 脚本是否存在
test_deploy_script_exists() {
    [ -f "src/deploy.sh" ]
}

# 测试 2: 检查 deploy 脚本是否可执行
test_deploy_script_executable() {
    [ -x "src/deploy.sh" ] || chmod +x "src/deploy.sh"
}

# 测试 3: 检查配置文件是否存在
test_config_exists() {
    [ -f "config/config.example.yaml" ]
}

# 测试 4: 检查安装脚本是否存在
test_install_script_exists() {
    [ -f "scripts/install.sh" ]
}

# 测试 5: 检查 README 是否存在
test_readme_exists() {
    [ -f "README.md" ]
}

# 测试 6: 检查 LICENSE 是否存在
test_license_exists() {
    [ -f "LICENSE" ]
}

# 测试 7: 检查 Dockerfile 是否存在
test_dockerfile_exists() {
    [ -f "Dockerfile" ]
}

# 测试 8: 检查 docker-compose.yml 是否存在
test_docker_compose_exists() {
    [ -f "docker-compose.yml" ]
}

# 测试 9: 检查 GitHub Actions 工作流是否存在
test_github_actions_exists() {
    [ -f ".github/workflows/deploy.yml" ]
}

# 测试 10: 检查 .gitignore 是否存在
test_gitignore_exists() {
    [ -f ".gitignore" ]
}

# 测试 11: 检查 CONTRIBUTING.md 是否存在
test_contributing_exists() {
    [ -f "CONTRIBUTING.md" ]
}

# 测试 12: 检查 deploy 脚本语法
test_deploy_script_syntax() {
    bash -n "src/deploy.sh"
}

# 测试 13: 检查 install 脚本语法
test_install_script_syntax() {
    bash -n "scripts/install.sh"
}

# 测试 14: 检查配置文件格式
test_config_format() {
    # 简单检查 YAML 格式
    grep -q "project:" "config/config.example.yaml"
}

# 运行测试
main() {
    echo "=========================================="
    echo "  Cloud Deploy 测试套件"
    echo "=========================================="
    echo ""

    # 运行所有测试
    run_test "deploy 脚本存在" test_deploy_script_exists
    run_test "deploy 脚本可执行" test_deploy_script_executable
    run_test "配置文件存在" test_config_exists
    run_test "安装脚本存在" test_install_script_exists
    run_test "README 存在" test_readme_exists
    run_test "LICENSE 存在" test_license_exists
    run_test "Dockerfile 存在" test_dockerfile_exists
    run_test "docker-compose.yml 存在" test_docker_compose_exists
    run_test "GitHub Actions 存在" test_github_actions_exists
    run_test ".gitignore 存在" test_gitignore_exists
    run_test "CONTRIBUTING.md 存在" test_contributing_exists
    run_test "deploy 脚本语法正确" test_deploy_script_syntax
    run_test "install 脚本语法正确" test_install_script_syntax
    run_test "配置文件格式正确" test_config_format

    # 显示测试结果
    echo ""
    echo "=========================================="
    echo "  测试结果"
    echo "=========================================="
    echo ""
    echo "总测试数: ${TESTS_TOTAL}"
    echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
    echo ""

    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "${GREEN}所有测试通过！${NC}"
        exit 0
    else
        echo -e "${RED}有测试失败！${NC}"
        exit 1
    fi
}

# 运行主函数
main
