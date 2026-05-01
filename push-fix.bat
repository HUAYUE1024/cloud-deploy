@echo off
cd /d "%~dp0"
git add -A
git commit -m "fix: update GitHub Actions for shell project"
git push -u origin main
echo.
echo Done! Visit: https://github.com/HUAYUE1024/cloud-deploy
pause
