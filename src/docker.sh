#!/bin/bash
#
# Cloud Deploy - Docker 函数库
# 版本: 3.0.0
#

# 加载工具函数
SCRIPT_DIR_DOCKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR_DOCKER}/utils.sh" ] && source "${SCRIPT_DIR_DOCKER}/utils.sh"

# ============================================
# 镜像管理
# ============================================

# 构建 Docker 镜像
docker_build() {
    local image_name=$1
    local version=${2:-"latest"}
    local dockerfile=${3:-"Dockerfile"}
    local context=${4:-"."}
    local build_args=${5:-""}

    log_info "构建 Docker 镜像: ${image_name}:${version}"

    local build_cmd="docker build -t ${image_name}:${version}"

    if [ "${version}" != "latest" ]; then
        build_cmd="${build_cmd} -t ${image_name}:latest"
    fi

    build_cmd="${build_cmd} -f ${dockerfile}"

    # 添加构建参数
    if [ -n "${build_args}" ]; then
        while IFS='=' read -r key value; do
            [ -n "${key}" ] && build_cmd="${build_cmd} --build-arg ${key}=${value}"
        done <<< "${build_args}"
    fi

    build_cmd="${build_cmd} ${context}"

    if eval "${build_cmd}"; then
        log_info "镜像构建成功: ${image_name}:${version}"
        return 0
    else
        log_error "镜像构建失败: ${image_name}:${version}"
        return 1
    fi
}

# 推送 Docker 镜像
docker_push() {
    local image_name=$1
    local version=${2:-"latest"}
    local registry=${3:-""}

    local full_image="${image_name}:${version}"
    if [ -n "${registry}" ]; then
        full_image="${registry}/${full_image}"
    fi

    log_info "推送镜像: ${full_image}"

    if docker push "${full_image}"; then
        log_info "镜像推送成功: ${full_image}"
        return 0
    else
        log_error "镜像推送失败: ${full_image}"
        return 1
    fi
}

# 拉取 Docker 镜像
docker_pull() {
    local image_name=$1
    local version=${2:-"latest"}
    local registry=${3:-""}

    local full_image="${image_name}:${version}"
    if [ -n "${registry}" ]; then
        full_image="${registry}/${full_image}"
    fi

    log_info "拉取镜像: ${full_image}"

    if docker pull "${full_image}"; then
        log_info "镜像拉取成功: ${full_image}"
        return 0
    else
        log_error "镜像拉取失败: ${full_image}"
        return 1
    fi
}

# 保存镜像为 tar 文件
docker_save() {
    local image_name=$1
    local version=${2:-"latest"}
    local output_file=${3:-"/tmp/${image_name}-${version}.tar.gz"}

    log_info "保存镜像: ${image_name}:${version} -> ${output_file}"

    if docker save "${image_name}:${version}" | gzip > "${output_file}"; then
        local size=$(format_file_size $(get_file_size "${output_file}"))
        log_info "镜像已保存: ${output_file} (${size})"
        echo "${output_file}"
        return 0
    else
        log_error "镜像保存失败"
        return 1
    fi
}

# 加载镜像
docker_load() {
    local input_file=$1

    log_info "加载镜像: ${input_file}"

    if docker load < "${input_file}"; then
        log_info "镜像加载成功"
        return 0
    else
        log_error "镜像加载失败"
        return 1
    fi
}

# 清理未使用的镜像
docker_prune() {
    local force=${1:-false}

    log_info "清理未使用的 Docker 镜像..."

    local prune_cmd="docker image prune -f"

    if [ "${force}" = "true" ]; then
        prune_cmd="${prune_cmd} -a"
    fi

    eval "${prune_cmd}"
    log_info "镜像清理完成"
}

# ============================================
# 容器管理
# ============================================

# 启动容器
docker_run() {
    local image_name=$1
    local container_name=$2
    local ports=${3:-""}
    local volumes=${4:-""}
    local env_vars=${5:-""}
    local memory=${6:-""}
    local cpus=${7:-""}
    local restart_policy=${8:-"unless-stopped"}
    local extra_args=${9:-""}

    log_info "启动容器: ${container_name}"

    # 停止并删除旧容器
    docker stop "${container_name}" 2>/dev/null || true
    docker rm "${container_name}" 2>/dev/null || true

    local run_cmd="docker run -d --name ${container_name} --restart ${restart_policy}"

    # 添加端口映射
    if [ -n "${ports}" ]; then
        while IFS=',' read -ra PORT_LIST; do
            for port in "${PORT_LIST[@]}"; do
                run_cmd="${run_cmd} -p ${port}"
            done
        done <<< "${ports}"
    fi

    # 添加卷挂载
    if [ -n "${volumes}" ]; then
        while IFS=',' read -ra VOL_LIST; do
            for vol in "${VOL_LIST[@]}"; do
                run_cmd="${run_cmd} -v ${vol}"
            done
        done <<< "${volumes}"
    fi

    # 添加环境变量
    if [ -n "${env_vars}" ]; then
        while IFS=',' read -ra ENV_LIST; do
            for env in "${ENV_LIST[@]}"; do
                run_cmd="${run_cmd} -e ${env}"
            done
        done <<< "${env_vars}"
    fi

    # 添加资源限制
    [ -n "${memory}" ] && run_cmd="${run_cmd} --memory=${memory}"
    [ -n "${cpus}" ] && run_cmd="${run_cmd} --cpus=${cpus}"

    # 添加额外参数
    [ -n "${extra_args}" ] && run_cmd="${run_cmd} ${extra_args}"

    run_cmd="${run_cmd} ${image_name}"

    if eval "${run_cmd}"; then
        log_info "容器启动成功: ${container_name}"
        return 0
    else
        log_error "容器启动失败: ${container_name}"
        return 1
    fi
}

# 停止容器
docker_stop() {
    local container_name=$1
    local timeout=${2:-10}

    log_info "停止容器: ${container_name}"

    if docker stop -t "${timeout}" "${container_name}" 2>/dev/null; then
        log_info "容器已停止: ${container_name}"
        return 0
    else
        log_warn "容器未运行或不存在: ${container_name}"
        return 0
    fi
}

# 删除容器
docker_remove() {
    local container_name=$1
    local force=${2:-false}

    log_info "删除容器: ${container_name}"

    local rm_cmd="docker rm"
    [ "${force}" = "true" ] && rm_cmd="${rm_cmd} -f"

    if ${rm_cmd} "${container_name}" 2>/dev/null; then
        log_info "容器已删除: ${container_name}"
        return 0
    else
        log_warn "容器不存在: ${container_name}"
        return 0
    fi
}

# 重启容器
docker_restart() {
    local container_name=$1
    local timeout=${2:-10}

    log_info "重启容器: ${container_name}"

    if docker restart -t "${timeout}" "${container_name}"; then
        log_info "容器重启成功: ${container_name}"
        return 0
    else
        log_error "容器重启失败: ${container_name}"
        return 1
    fi
}

# 获取容器状态
docker_status() {
    local container_name=$1

    docker inspect --format='{{.State.Status}}' "${container_name}" 2>/dev/null || echo "not_found"
}

# 检查容器是否运行
docker_is_running() {
    local container_name=$1

    [ "$(docker_status "${container_name}")" = "running" ]
}

# 获取容器日志
docker_logs() {
    local container_name=$1
    local lines=${2:-100}
    local follow=${3:-false}

    local log_cmd="docker logs --tail ${lines}"
    [ "${follow}" = "true" ] && log_cmd="${log_cmd} -f"

    ${log_cmd} "${container_name}"
}

# 获取容器资源使用
docker_stats() {
    local container_name=$1

    docker stats --no-stream --format "CPU: {{.CPUPerc}} | MEM: {{.MemUsage}} | NET: {{.NetIO}}" "${container_name}" 2>/dev/null
}

# 等待容器健康
docker_wait_healthy() {
    local container_name=$1
    local timeout=${2:-60}
    local interval=${3:-2}

    log_info "等待容器健康: ${container_name}"

    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while [ $(date +%s) -lt ${end_time} ]; do
        local health=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "none")

        if [ "${health}" = "healthy" ]; then
            log_info "容器已健康: ${container_name}"
            return 0
        elif [ "${health}" = "none" ]; then
            # 没有健康检查，检查是否运行
            if docker_is_running "${container_name}"; then
                log_info "容器正在运行: ${container_name}"
                return 0
            fi
        fi

        sleep ${interval}
    done

    log_error "容器健康检查超时: ${container_name}"
    return 1
}

# ============================================
# Docker Compose 管理
# ============================================

# Docker Compose 启动
compose_up() {
    local compose_file=${1:-"docker-compose.yml"}
    local project_name=${2:-""}
    local services=${3:-""}
    local detach=${4:-true}

    log_info "启动 Docker Compose..."

    local up_cmd="docker-compose -f ${compose_file}"

    [ -n "${project_name}" ] && up_cmd="${up_cmd} -p ${project_name}"

    up_cmd="${up_cmd} up"
    [ "${detach}" = "true" ] && up_cmd="${up_cmd} -d"
    [ -n "${services}" ] && up_cmd="${up_cmd} ${services}"

    if eval "${up_cmd}"; then
        log_info "Docker Compose 启动成功"
        return 0
    else
        log_error "Docker Compose 启动失败"
        return 1
    fi
}

# Docker Compose 停止
compose_down() {
    local compose_file=${1:-"docker-compose.yml"}
    local project_name=${2:-""}
    local volumes=${3:-false}

    log_info "停止 Docker Compose..."

    local down_cmd="docker-compose -f ${compose_file}"

    [ -n "${project_name}" ] && down_cmd="${down_cmd} -p ${project_name}"

    down_cmd="${down_cmd} down"
    [ "${volumes}" = "true" ] && down_cmd="${down_cmd} -v"

    if eval "${down_cmd}"; then
        log_info "Docker Compose 已停止"
        return 0
    else
        log_error "Docker Compose 停止失败"
        return 1
    fi
}

# Docker Compose 构建
compose_build() {
    local compose_file=${1:-"docker-compose.yml"}
    local project_name=${2:-""}
    local services=${3:-""}
    local no_cache=${4:-false}

    log_info "构建 Docker Compose..."

    local build_cmd="docker-compose -f ${compose_file}"

    [ -n "${project_name}" ] && build_cmd="${build_cmd} -p ${project_name}"

    build_cmd="${build_cmd} build"
    [ "${no_cache}" = "true" ] && build_cmd="${build_cmd} --no-cache"
    [ -n "${services}" ] && build_cmd="${build_cmd} ${services}"

    if eval "${build_cmd}"; then
        log_info "Docker Compose 构建成功"
        return 0
    else
        log_error "Docker Compose 构建失败"
        return 1
    fi
}

# Docker Compose 拉取
compose_pull() {
    local compose_file=${1:-"docker-compose.yml"}
    local project_name=${2:-""}
    local services=${3:-""}

    log_info "拉取 Docker Compose 镜像..."

    local pull_cmd="docker-compose -f ${compose_file}"

    [ -n "${project_name}" ] && pull_cmd="${pull_cmd} -p ${project_name}"

    pull_cmd="${pull_cmd} pull"
    [ -n "${services}" ] && pull_cmd="${pull_cmd} ${services}"

    if eval "${pull_cmd}"; then
        log_info "Docker Compose 镜像拉取成功"
        return 0
    else
        log_error "Docker Compose 镜像拉取失败"
        return 1
    fi
}

# ============================================
# 仓库管理
# ============================================

# Docker 登录
docker_login() {
    local registry=${1:-""}
    local username=$2
    local password=$3

    log_info "Docker 登录: ${registry:-Docker Hub}"

    if echo "${password}" | docker login "${registry}" -u "${username}" --password-stdin; then
        log_info "Docker 登录成功"
        return 0
    else
        log_error "Docker 登录失败"
        return 1
    fi
}

# Docker 登出
docker_logout() {
    local registry=${1:-""}

    docker logout "${registry}" 2>/dev/null
    log_info "Docker 已登出"
}

# 标记镜像
docker_tag() {
    local source_image=$1
    local target_image=$2

    log_info "标记镜像: ${source_image} -> ${target_image}"

    if docker tag "${source_image}" "${target_image}"; then
        log_info "镜像标记成功"
        return 0
    else
        log_error "镜像标记失败"
        return 1
    fi
}

# ============================================
# 网络管理
# ============================================

# 创建 Docker 网络
docker_network_create() {
    local network_name=$1
    local driver=${2:-"bridge"}

    log_info "创建 Docker 网络: ${network_name}"

    if docker network create --driver "${driver}" "${network_name}" 2>/dev/null; then
        log_info "网络创建成功: ${network_name}"
        return 0
    else
        log_warn "网络已存在或创建失败: ${network_name}"
        return 0
    fi
}

# 删除 Docker 网络
docker_network_remove() {
    local network_name=$1

    log_info "删除 Docker 网络: ${network_name}"

    if docker network rm "${network_name}" 2>/dev/null; then
        log_info "网络删除成功: ${network_name}"
        return 0
    else
        log_warn "网络不存在或删除失败: ${network_name}"
        return 0
    fi
}

# ============================================
# 卷管理
# ============================================

# 创建 Docker 卷
docker_volume_create() {
    local volume_name=$1

    log_info "创建 Docker 卷: ${volume_name}"

    if docker volume create "${volume_name}" 2>/dev/null; then
        log_info "卷创建成功: ${volume_name}"
        return 0
    else
        log_warn "卷已存在或创建失败: ${volume_name}"
        return 0
    fi
}

# 删除 Docker 卷
docker_volume_remove() {
    local volume_name=$1
    local force=${2:-false}

    log_info "删除 Docker 卷: ${volume_name}"

    local rm_cmd="docker volume rm"
    [ "${force}" = "true" ] && rm_cmd="${rm_cmd} -f"

    if ${rm_cmd} "${volume_name}" 2>/dev/null; then
        log_info "卷删除成功: ${volume_name}"
        return 0
    else
        log_warn "卷不存在或删除失败: ${volume_name}"
        return 0
    fi
}

# ============================================
# 远程 Docker 操作
# ============================================

# 远程构建并部署
docker_remote_deploy() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=${5:-"latest"}
    local container_name=${6:-"${image_name}"}
    local ports=${7:-""}
    local volumes=${8:-""}
    local env_vars=${9:-""}

    log_info "远程 Docker 部署: ${host}"

    # 构建镜像
    docker_build "${image_name}" "${version}"

    # 保存镜像
    local image_file=$(docker_save "${image_name}" "${version}")

    # 上传镜像
    scp_upload "${host}" "${user}" "${password}" "${image_file}" "/tmp/"

    # 远程部署
    ssh_connect "${host}" "${user}" "${password}" "
        # 加载镜像
        docker load < /tmp/$(basename ${image_file})

        # 停止旧容器
        docker stop ${container_name} 2>/dev/null || true
        docker rm ${container_name} 2>/dev/null || true

        # 启动新容器
        docker run -d \
            --name ${container_name} \
            --restart unless-stopped \
            -p ${ports:-80:80} \
            ${volumes:+-v ${volumes}} \
            ${env_vars:+-e ${env_vars}} \
            ${image_name}:${version}

        # 等待容器启动
        sleep 5

        # 检查容器状态
        if ! docker ps | grep -q ${container_name}; then
            echo '容器启动失败'
            docker logs ${container_name}
            exit 1
        fi

        # 清理临时文件
        rm -f /tmp/$(basename ${image_file})
    "

    # 清理本地临时文件
    rm -f "${image_file}"

    log_info "远程 Docker 部署完成"
}

# 远程蓝绿部署
docker_remote_blue_green() {
    local host=$1
    local user=$2
    local password=$3
    local image_name=$4
    local version=${5:-"latest"}
    local blue_port=${6:-8080}
    local green_port=${7:-8081}
    local health_url=${8:-"/health"}

    log_info "远程蓝绿部署: ${host}"

    # 获取当前活跃环境
    local current_env=$(ssh_connect "${host}" "${user}" "${password}" "
        docker ps --format '{{.Names}}' | grep -E '^(blue|green)$' | head -1
    " 2>/dev/null || echo "")

    # 确定新环境和端口
    local new_env new_port
    if [ "${current_env}" = "blue" ]; then
        new_env="green"
        new_port="${green_port}"
    else
        new_env="blue"
        new_port="${blue_port}"
    fi

    log_info "当前环境: ${current_env:-无}, 部署到: ${new_env} (端口: ${new_port})"

    # 构建并保存镜像
    docker_build "${image_name}" "${version}"
    local image_file=$(docker_save "${image_name}" "${version}")

    # 上传镜像
    scp_upload "${host}" "${user}" "${password}" "${image_file}" "/tmp/"

    # 部署新版本
    ssh_connect "${host}" "${user}" "${password}" "
        docker load < /tmp/$(basename ${image_file})

        docker stop ${new_env} 2>/dev/null || true
        docker rm ${new_env} 2>/dev/null || true

        docker run -d \
            --name ${new_env} \
            --restart unless-stopped \
            -p ${new_port}:80 \
            ${image_name}:${version}

        rm -f /tmp/$(basename ${image_file})
    "

    rm -f "${image_file}"

    log_info "蓝绿部署完成，新环境: ${new_env}"
}

# 导出所有函数
export -f docker_build docker_push docker_pull docker_save docker_load docker_prune
export -f docker_run docker_stop docker_remove docker_restart docker_status docker_is_running
export -f docker_logs docker_stats docker_wait_healthy
export -f compose_up compose_down compose_build compose_pull
export -f docker_login docker_logout docker_tag
export -f docker_network_create docker_network_remove
export -f docker_volume_create docker_volume_remove
export -f docker_remote_deploy docker_remote_blue_green
