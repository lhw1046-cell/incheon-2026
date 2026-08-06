@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   인천 2026 대시보드 배포
echo ============================================
echo.

if not exist ".git" (
  echo [!] 아직 Git 저장소가 아닙니다.
  echo     README.md 의 "최초 1회 설정" 을 먼저 진행해 주세요.
  echo.
  pause
  exit /b 1
)

echo [1/3] 대시보드를 index.html 로 복사
copy /Y "인천 2026 대시보드.html" "index.html" >nul
if errorlevel 1 (
  echo [!] 대시보드 파일을 찾을 수 없습니다.
  pause
  exit /b 1
)

echo [2/3] 변경사항 커밋
git add -A
git diff --cached --quiet
if not errorlevel 1 (
  echo     변경된 내용이 없습니다. 배포를 건너뜁니다.
  echo.
  pause
  exit /b 0
)
for /f "tokens=1-3 delims=- " %%a in ("%date%") do set D=%%a-%%b-%%c
git commit -m "기록 갱신 %D%" >nul

echo [3/3] GitHub 로 푸시
git push
if errorlevel 1 (
  echo.
  echo [!] 푸시 실패. 인터넷 연결 또는 GitHub 로그인 상태를 확인하세요.
  pause
  exit /b 1
)

echo.
echo ============================================
echo   완료. 1~2분 뒤 아래 주소에 반영됩니다.
echo.
for /f "tokens=*" %%u in ('git remote get-url origin') do echo   %%u
echo ============================================
echo.
pause
