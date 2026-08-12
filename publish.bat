@echo off
setlocal EnableExtensions
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
  pause
  exit /b 1
)

set "UPDATER="
for /d %%D in (*) do if exist "%%D\update_soccer365.ps1" set "UPDATER=%%D\update_soccer365.ps1"
if not defined UPDATER (
  echo [!] update_soccer365.ps1 not found.
  pause
  exit /b 1
)

echo [1/4] Update from Soccer365
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%"
if errorlevel 1 (
  echo.
  echo [!] Soccer365 update failed. Nothing was published.
  echo     Close the Excel workbook, check the internet connection,
  echo     and try again.
  pause
  exit /b 1
)
echo.

echo [2/4] Commit local changes
git add -A
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "update dashboard from Soccer365"
) else (
  echo     nothing new to commit.
)
echo.

echo [3/4] Sync with GitHub
git fetch origin
if errorlevel 1 goto :gitfail
git merge -X ours --no-edit origin/main
if errorlevel 1 goto :mergefail
echo.

echo [4/4] Push
git push
if errorlevel 1 goto :pushfail

echo.
echo ==========================================
echo   Done. Live in 1-2 minutes:
echo   https://lhw1046-cell.github.io/incheon-2026/
echo ==========================================
echo.
pause
exit /b 0

:gitfail
echo [!] GitHub fetch failed. Check internet or GitHub login.
pause
exit /b 1

:mergefail
echo [!] Merge conflict. Nothing was pushed.
pause
exit /b 1

:pushfail
echo [!] Push failed. Check internet or GitHub login.
pause
exit /b 1
