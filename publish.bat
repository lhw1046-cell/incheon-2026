@echo off
setlocal
cd /d "%~dp0"

echo ==========================================
echo   Incheon 2026 Dashboard - Publish
echo ==========================================
echo.

if not exist ".git" (
  echo [!] Not a git repository. See README.md
  echo.
  pause
  exit /b 1
)

echo [1/4] Copy dashboard to index.html
copy /Y "인천 2026 대시보드.html" "index.html" >nul
if errorlevel 1 (
  echo [!] Dashboard file not found.
  pause
  exit /b 1
)

echo [2/4] Commit local changes
git add -A
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "update dashboard" >nul
  echo     committed.
) else (
  echo     nothing new to commit.
)

echo [3/4] Sync with GitHub
git fetch origin
git merge -X ours --no-edit origin/main
if errorlevel 1 (
  echo.
  echo [!] Merge conflict. Run:  git merge --abort
  echo     then ask Claude to resolve it.
  pause
  exit /b 1
)

echo [4/4] Push
git push
if errorlevel 1 (
  echo.
  echo [!] Push failed. Check internet / GitHub login.
  pause
  exit /b 1
)

echo.
echo ==========================================
echo   Done. Live in 1-2 minutes:
echo   https://lhw1046-cell.github.io/incheon-2026/
echo ==========================================
echo.
pause
