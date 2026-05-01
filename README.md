# Cloud Deploy - 企业级多云部署平台

<div align="center">

![Version](https://img.shields.io/badge/version-3.1.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos-lightgrey.svg)
![Docker](https://img.shields.io/badge/docker-supported-2496ED.svg)
![Kubernetes](https://img.shields.io/badge/kubernetes-supported-326CE5.svg)

**一键部署到任意云服务器，支持 Docker、Kubernetes、蓝绿部署、金丝雀发布**

[English](./docs/en/README.md) | [中文](./README.md)

</div>

---

## 功能特性

### 核心功能

- **多云统一管理** - 支持阿里云、腾讯云、AWS、华为云、Google Cloud、私有云
- **一键部署** - 只需输入 IP、用户名、密码即可完成部署
- **多语言支持** - 自动检测 Node.js、Python、Java、Go、PHP、Rust、Ruby、C++
- **Docker 支持** - 容器化部署、镜像构建、仓库推送
- **Kubernetes 支持** - K8s 集群部署、滚动更新、自动扩缩容

### 部署策略

| 策略 | 说明 | 适用场景 |
|------|------|----------|
| 直接部署 | 停止旧版本，部署新版本 | 开发环境、小型项目 |
| 滚动更新 | 逐步替换实例，零停机 | 生产环境、多实例服务 |
| 蓝绿部署 | 两套环境切换，快速回滚 | 关键业务、高可用要求 |
| 金丝雀发布 | 小流量验证，逐步扩大 | 大规模系统、风险控制 |

### 企业级特性

- **自动回滚** - 健康检查失败自动回滚到上一版本
- **健康检查** - 部署后自动验证服务状态
- **监控告警** - CPU、内存、磁盘、错误率实时监控
- **多渠道通知** - 邮件、钉钉、Slack、企业微信、飞书
- **审计日志** - 完整记录所有部署操作
- **备份管理** - 自动备份、多版本保留、远程存储
- **安全加固** - 密钥管理、IP 白名单、SSL/TLS、MFA

---

## 快速开始

### 安装

```bash
# 一键安装
curl -fsSL https://raw.githubusercontent.com/HUAYUE1024/cloud-deploy/main/scripts/install.sh | bash

# 或手动安装
git clone https://github.com/HUAYUE1024/cloud-deploy.git
cd cloud-deploy
chmod +x scripts/install.sh
./scripts/install.sh
```

### 初始化配置

```bash
# 运行配置向导
deploy init --wizard

# 或手动配置
deploy config set project.name "my-app"
deploy config set server.production.host "192.168.1.100"
deploy config set server.production.user "root"
```

### 一键部署

```bash
# 交互式部署（按提示输入信息）
deploy

# 指定环境部署
deploy --env production

# Docker 部署
deploy --host 192.168.1.100 --user root --password yourpassword --method docker

# 蓝绿部署
deploy --env production --strategy blue-green

# 金丝雀发布
deploy --env production --strategy canary
```

---

## 使用指南

### 基础命令

```bash
# 初始化配置
deploy init

# 执行部署
deploy --env production

# 回滚到上一版本
deploy --rollback

# 回滚到指定版本
deploy --rollback --version v1.2.0

# 查看部署状态
deploy --status

# 查看部署历史
deploy --history

# 查看服务器日志
deploy --logs --env production

# 实时跟踪日志
deploy --logs --follow

# 系统监控
deploy --monitor

# 健康检查
deploy --health http://example.com
```

### 部署方式

#### 直接部署

```bash
deploy --method direct
```

流程：停止服务 → 备份 → 上传代码 → 安装依赖 → 启动服务

#### Docker 部署

```bash
deploy --method docker
```

流程：构建镜像 → 推送仓库 → 拉取镜像 → 启动容器

#### Kubernetes 部署

```bash
deploy --method kubernetes
```

流程：构建镜像 → 推送仓库 → 更新 Deployment → 滚动更新

### 部署策略

#### 蓝绿部署

```bash
deploy --strategy blue-green
```

1. 部署新版本到备用环境（绿色）
2. 运行健康检查
3. 切换流量到新版本
4. 停止旧版本（蓝色）

#### 金丝雀发布

```bash
deploy --strategy canary --canary-percent 10
```

1. 部署新版本到部分服务器（10% 流量）
2. 监控错误率和性能
3. 逐步扩大流量比例（10% → 30% → 50% → 100%）
4. 异常时自动回滚

---

## 配置说明

### 配置文件

配置文件位于 `~/.deploy-tools/config.yaml`，支持以下配置项：

```yaml
# 项目配置
project:
  name: my-app
  type: auto  # 自动检测项目类型
  healthCheckUrl: /health
  healthCheckTimeout: 30

# 服务器配置
servers:
  production:
    host: 192.168.1.100
    user: root
    password: ${SERVER_PASSWORD}  # 支持环境变量
    deployPath: /var/www/app
    method: docker
    strategy: blue-green

  staging:
    host: 192.168.1.101
    user: root
    password: ${SERVER_PASSWORD}
    deployPath: /var/www/app
    method: direct
    strategy: rolling

# 通知配置
notifications:
  email:
    enabled: true
    smtp:
      host: smtp.gmail.com
      port: 587
      user: ${SMTP_USER}
      password: ${SMTP_PASSWORD}
    recipients:
      - admin@example.com

  dingtalk:
    enabled: true
    webhook: ${DINGTALK_WEBHOOK}

  slack:
    enabled: false
    webhook: ${SLACK_WEBHOOK}

  wechat:
    enabled: false
    webhook: ${WECHAT_WEBHOOK}

  feishu:
    enabled: false
    webhook: ${FEISHU_WEBHOOK}
```

### 环境变量

创建 `.env` 文件存储敏感信息：

```env
# 服务器密码
SERVER_PASSWORD=your-secure-password

# Docker 仓库
DOCKER_USER=your-docker-username
DOCKER_PASSWORD=your-docker-password

# 邮件配置
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password

# 通知 Webhook
DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx
SLACK_WEBHOOK=https://hooks.slack.com/services/xxx
WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx
FEISHU_WEBHOOK=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

---

## 项目结构

```
cloud-deploy/
├── src/                        # 源代码
│   ├── deploy.sh              # 主部署脚本（模块化架构）
│   ├── utils.sh               # 工具函数库（日志、验证、系统信息等）
│   ├── docker.sh              # Docker 函数库（镜像、容器、Compose 管理）
│   ├── notifications.sh       # 通知函数库（邮件、钉钉、Slack、企业微信、飞书）
│   └── monitoring.sh          # 监控函数库（健康检查、系统监控、告警）
├── config/                     # 配置文件
│   └── config.example.yaml   # 配置示例
├── scripts/                    # 辅助脚本
│   ├── install.sh             # 安装脚本
│   └── uninstall.sh           # 卸载脚本
├── tests/                      # 测试
│   └── run-tests.sh           # 测试脚本
├── .github/                    # GitHub 配置
│   └── workflows/
│       └── deploy.yml         # GitHub Actions 工作流
├── Dockerfile                  # Docker 镜像
├── docker-compose.yml          # Docker Compose 配置
├── LICENSE                     # MIT 许可证
├── README.md                   # 项目说明
└── CONTRIBUTING.md             # 贡献指南
```

### 模块说明

| 模块 | 文件 | 功能 |
|------|------|------|
| 主脚本 | `deploy.sh` | 部署流程控制、CLI 接口、项目构建 |
| 工具库 | `utils.sh` | 日志系统、系统信息、验证、加密、锁机制 |
| Docker | `docker.sh` | 镜像构建/推送/拉取、容器管理、Compose、蓝绿/金丝雀部署 |
| 通知 | `notifications.sh` | 邮件、钉钉、Slack、企业微信、飞书、自定义 Webhook |
| 监控 | `monitoring.sh` | HTTP/TCP/Docker 健康检查、系统监控、资源告警、日志监控 |

---

## 支持的云服务商

| 云服务商 | ECS/VM | 容器服务 | Serverless |
|----------|--------|----------|------------|
| 阿里云   | ✅     | ✅ ACK   | ✅ FC      |
| 腾讯云   | ✅     | ✅ TKE   | ✅ SCF     |
| AWS      | ✅     | ✅ EKS   | ✅ Lambda  |
| 华为云   | ✅     | ✅ CCE   | ✅ FunctionGraph |
| Google Cloud | ✅ | ✅ GKE   | ✅ Cloud Functions |
| 私有云   | ✅     | ✅ K8s   | -          |

---

## 支持的项目类型

| 语言/框架 | 检测文件 | 构建命令 | 测试命令 |
|-----------|----------|----------|----------|
| Node.js   | package.json | npm run build | npm test |
| Python    | requirements.txt | pip install | pytest |
| Java      | pom.xml | mvn package | mvn test |
| Go        | go.mod | go build | go test |
| PHP       | composer.json | composer install | phpunit |
| Rust      | Cargo.toml | cargo build | cargo test |
| Ruby      | Gemfile | bundle install | rspec |
| Docker    | Dockerfile | docker build | - |

---

## 最佳实践

### 1. 使用密钥认证

```bash
# 生成 SSH 密钥
ssh-keygen -t rsa -b 4096 -C "deploy@example.com"

# 复制到服务器
ssh-copy-id root@192.168.1.100
```

### 2. 环境隔离

```bash
# 部署到测试环境
deploy --env staging

# 部署到生产环境
deploy --env production
```

### 3. 自动化测试

```yaml
# config.yaml
project:
  test:
    enabled: true
    command: "npm test"
    coverage:
      enabled: true
      threshold: 80
```

### 4. 监控告警

```yaml
# config.yaml
servers:
  production:
    monitoring:
      enabled: true
      interval: 60
      alerts:
        cpu_threshold: 80
        memory_threshold: 85
        error_rate_threshold: 0.05
```

### 5. 备份策略

```yaml
# config.yaml
servers:
  production:
    backup:
      enabled: true
      schedule: "0 2 * * *"  # 每天凌晨2点
      retention:
        daily: 7
        weekly: 4
        monthly: 12
```

### 6. 多渠道通知

```yaml
# config.yaml
notifications:
  email:
    enabled: true
    recipients:
      - admin@example.com
  dingtalk:
    enabled: true
    webhook: ${DINGTALK_WEBHOOK}
  slack:
    enabled: true
    webhook: ${SLACK_WEBHOOK}
    channel: "#deployments"
```

---

## 故障排查

### 连接失败

```bash
# 测试 SSH 连接
deploy test-connection --host 192.168.1.100 --user root

# 检查防火墙
telnet 192.168.1.100 22
```

### 部署失败

```bash
# 查看详细日志
deploy logs --level debug

# 手动回滚
deploy --rollback --force
```

### 健康检查失败

```bash
# 手动测试
curl -v http://192.168.1.100/health

# 检查服务状态
ssh root@192.168.1.100 "systemctl status app"
```

### 系统监控

```bash
# 查看系统状态
deploy --monitor

# 检查服务健康
deploy --health http://192.168.1.100/health
```

---

## 贡献指南

欢迎贡献代码！请查看 [CONTRIBUTING.md](./CONTRIBUTING.md) 了解详情。

### 开发环境

```bash
# 克隆仓库
git clone https://github.com/HUAYUE1024/cloud-deploy.git
cd cloud-deploy

# 安装依赖
./scripts/install.sh

# 运行测试
./tests/run-tests.sh
```

### 提交代码

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

---

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](./LICENSE) 文件

---

## 联系方式

- **作者**: HUAYUE1024
- **邮箱**: winc521521@gmail.com
- **GitHub**: [@HUAYUE1024](https://github.com/HUAYUE1024)

---

## 致谢

感谢所有贡献者的支持！

---

<div align="center">

**如果这个项目对你有帮助，请给一个 Star ⭐**

</div>
