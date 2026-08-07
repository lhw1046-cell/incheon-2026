@echo off
setlocal
cd /d "%~dp0"

echo ==========================================
echo   Incheon 2026 Dashboard - Publish
echo ==========================================
echo.

if not exist ".git" (
  echo [!] Not a git repository. See README.md
  pause
  exit /b 1
)

if not exist "index.html" (
  echo [!] index.html not found.
  echo     Ask Claude to regenerate the dashboard first.
  pause
  exit /b 1
)

echo [1/3] Commit local changes
git add -A
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "update dashboard"
) else (
  echo     nothing new to commit.
)
echo.

echo [2/3] Sync with GitHub
git fetch origin
git merge -X ours --no-edit origin/main
if errorlevel 1 (
  echo.
  echo [!] Merge conflict. Run:  git merge --abort
  echo     then ask Claude to resolve it.
  pause
  exit /b 1
)
echo.

echo [3/3] Push
git push
if errorlevel 1 (
  echo.
  echo [!] Push failed. Check internet or GitHub login.
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
