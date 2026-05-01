@echo off
cd /d "%~dp0"

echo ========================================
echo  Cloud Deploy - Push Optimized Code
echo ========================================
echo.

echo [1/4] Adding all changes...
git add -A

echo [2/4] Committing changes...
git commit -m "refactor: modularize codebase into separate function libraries

- Created utils.sh: logging, system info, validation, encoding, security
- Created docker.sh: Docker image/container/compose management
- Created notifications.sh: email, DingTalk, Slack, WeChat, Feishu, webhook
- Created monitoring.sh: health checks, system monitoring, resource alerts
- Refactored deploy.sh to use modular libraries (v3.1.0)
- Updated config.example.yaml with improved structure
- Enhanced install.sh with better OS detection and error handling
- Updated README.md with modular architecture documentation"

echo [3/4] Pushing to GitHub...
git push -u origin main

echo.
echo ========================================
echo  Done! Visit: https://github.com/HUAYUE1024/cloud-deploy
echo ========================================
pause
