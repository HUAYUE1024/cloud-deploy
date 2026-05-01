# Cloud Deploy Dockerfile
# 用于构建部署工具的 Docker 镜像

FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    sshpass \
    openssh-client \
    ca-certificates \
    gnupg \
    lsb-release \
    mailutils \
    && rm -rf /var/lib/apt/lists/*

# 安装 yq
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq

# 安装 Docker CLI
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /app

# 复制脚本
COPY src/deploy.sh /usr/local/bin/deploy
COPY config/config.example.yaml /app/config/
COPY scripts/install.sh /app/scripts/

# 设置权限
RUN chmod +x /usr/local/bin/deploy \
    && chmod +x /app/scripts/install.sh

# 创建配置目录
RUN mkdir -p ~/.deploy-tools \
    && cp /app/config/config.example.yaml ~/.deploy-tools/config.yaml

# 设置环境变量
ENV DEPLOY_CONFIG="/root/.deploy-tools/config.yaml"

# 入口点
ENTRYPOINT ["deploy"]

# 默认参数
CMD ["--help"]
