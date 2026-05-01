@echo off
cd /d "%~dp0"
echo Pushing to GitHub...
git push -u origin main
echo.
echo Done! Visit: https://github.com/HUAYUE1024/cloud-deploy
pause
