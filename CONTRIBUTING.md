# 贡献指南

感谢您对 Cloud Deploy 项目的关注！我们欢迎任何形式的贡献。

## 如何贡献

### 报告问题

1. 使用 GitHub Issues 报告 bug
2. 描述问题的详细信息
3. 提供复现步骤
4. 附上相关日志

### 提交代码

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

### 代码规范

- 使用 ShellCheck 检查 Shell 脚本
- 遵循 Google Shell Style Guide
- 添加必要的注释
- 保持代码简洁

### 提交信息规范

使用 Conventional Commits 规范：

```
<type>(<scope>): <subject>

<body>

<footer>
```

类型：
- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档更新
- `style`: 代码格式
- `refactor`: 重构
- `test`: 测试
- `chore`: 构建/工具

示例：
```
feat(deploy): 添加金丝雀部署支持

- 支持按百分比分流
- 自动监控错误率
- 异常时自动回滚

Closes #123
```

### 开发环境

```bash
# 克隆仓库
git clone https://github.com/HUAYUE1024/cloud-deploy.git
cd cloud-deploy

# 安装依赖
./scripts/setup.sh

# 运行测试
./tests/run-tests.sh

# 运行 ShellCheck
shellcheck src/*.sh
```

### 测试

- 编写单元测试
- 确保所有测试通过
- 保持测试覆盖率

### 文档

- 更新 README.md
- 添加使用示例
- 完善 API 文档

## 行为准则

- 尊重他人
- 保持友善
- 接受批评
- 关注问题本身

## 许可证

贡献的代码将采用 MIT 许可证。

## 联系方式

如有问题，请通过以下方式联系：

- GitHub Issues
- Email: huayue1024@example.com

感谢您的贡献！
