@echo off
cd /d "%~dp0"

echo Cleaning repository...
git rm -f push-now.bat push-to-github.bat push.bat create-and-push.bat 2>nul
git commit -m "chore: remove batch files with secrets" 2>nul

echo Rewriting history...
git filter-branch --force --index-filter "git rm -f --cached --ignore-unmatch push-now.bat push-to-github.bat push.bat create-and-push.bat" --prune-empty --tag-name-filter cat -- --all

echo Pushing...
git push -u origin main --force

echo.
echo Done! Visit: https://github.com/HUAYUE1024/cloud-deploy
pause
