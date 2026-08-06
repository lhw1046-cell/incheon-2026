@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   GitHub 최초 업로드
echo   https://github.com/lhw1046-cell/incheon-2026
echo ============================================
echo.
echo 브라우저가 열리면 GitHub 로그인을 진행해 주세요.
echo (한 번만 하면 이후로는 자동입니다)
echo.

git push -u origin main

if errorlevel 1 (
  echo.
  echo ------------------------------------------------
  echo  [!] 실패했습니다. 아래를 확인해 주세요.
  echo.
  echo   1. github.com/new 에서 저장소를 만드셨나요?
  echo      이름: incheon-2026  /  Public
  echo      README·gitignore·license 는 체크 안 함
  echo.
  echo   2. Git 이 설치돼 있나요?  git --version
  echo      없으면 https://git-scm.com/download/win
  echo ------------------------------------------------
  echo.
  pause
  exit /b 1
)

echo.
echo ============================================
echo   업로드 완료.
echo.
echo   다음: 저장소 Settings - Pages 에서
echo         Branch: main / (root) 선택 후 Save
echo.
echo   1~2분 뒤 아래 주소에서 열립니다.
echo   https://lhw1046-cell.github.io/incheon-2026/
echo ============================================
echo.
pause
