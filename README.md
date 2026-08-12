# 인천 유나이티드 2026 시즌 기록

K리그1 2026 시즌 인천 유나이티드 경기·출전·순위 기록과 대시보드.

**대시보드 →** https://lhw1046-cell.github.io/incheon-2026/

---

## 파일 구성

| 파일 | 설명 |
|---|---|
| `인천 2026 기록.xlsx` | 원본 기록 워크북 (경기기록 · 출전기록 · 리그순위 · 차트) |
| `인천 2026 대시보드.html` | 생성된 대시보드 |
| `index.html` | 위 파일의 사본 — GitHub Pages가 이걸 띄웁니다 |
| `publish.bat` | 더블클릭 한 번으로 배포 |
| `인천기록_도구/` | 갱신 스크립트 일체 |

---

## 최초 1회 설정

### 1. Git 설치 확인

명령 프롬프트에서:

```
git --version
```

버전이 안 나오면 <https://git-scm.com/download/win> 에서 설치.
설치 중 **"Git Credential Manager"** 옵션은 켜둔 채로 진행하세요 (로그인이 편해집니다).

### 2. GitHub에 저장소 만들기

1. <https://github.com/new> 접속
2. **Repository name**: `incheon-2026`
3. **Public** 선택
4. README·.gitignore·license는 **아무것도 체크하지 않기** (이미 있습니다)
5. **Create repository**

### 3. 이 폴더를 저장소에 연결

이 폴더에서 주소창에 `cmd` 를 입력해 명령 프롬프트를 연 뒤:

```
git remote add origin https://github.com/<깃허브아이디>/incheon-2026.git
git branch -M main
git push -u origin main
```

첫 푸시 때 브라우저가 열리면서 GitHub 로그인을 요청합니다. 로그인하면 이후로는 자동입니다.

### 4. GitHub Pages 켜기

1. 저장소 → **Settings** → 왼쪽 메뉴 **Pages**
2. **Source**: `Deploy from a branch`
3. **Branch**: `main` / `/ (root)` → **Save**
4. 1~2분 뒤 페이지 상단에 주소가 뜹니다

---

## 경기 후 갱신

**`publish.bat`만 더블클릭하면 됩니다.**

배치파일이 다음 작업을 순서대로 자동 실행합니다.

1. Soccer365에서 K리그1 2026 순위표·전체 결과·향후 일정·인천 선수 기록 수집
2. 새로 끝난 인천 경기의 선발 명단·실제 교체 투입 명단·득점·도움·관중·주심 수집
3. `인천 2026 기록.xlsx`, `data.json`, `인천 2026 대시보드.html`, `index.html` 갱신
4. Git 커밋·GitHub 동기화·푸시

정상 완료 후 1~2분이면 GitHub Pages에 반영됩니다. 수집이나 Excel 저장에 실패하면
배포 전에 중단되므로, 깨진 데이터가 GitHub에 올라가지 않습니다.

### 실행 조건

- 인터넷 연결
- Microsoft Excel 설치
- Google Chrome 또는 Microsoft Edge 설치
- 갱신할 때 `인천 2026 기록.xlsx`를 닫아둘 것

선수 영문명→한글명과 주심명 매핑은
`인천기록_도구/soccer365_config.json`에서 관리합니다. 시즌 중 새 선수가 등록되어
매핑이 없으면 영문명을 그대로 보존하고 경고를 표시합니다.

---

## 참고

- 이 폴더는 OneDrive로 동기화됩니다. Git 저장소와 OneDrive를 함께 쓰면 드물게 충돌이
  날 수 있으니, 이상하면 `.git` 폴더를 OneDrive 동기화에서 제외하세요.
- 엑셀 파일이 열려 있으면 갱신 스크립트가 저장에 실패합니다. 갱신 전에 닫아주세요.
- Soccer365가 일시적으로 응답하지 않거나 차단 화면을 보이면 잠시 후 다시 실행하세요.
- 네이버스포츠와 FotMob은 이 자동화에서 사용하지 않습니다.
- 순위·경기 결과·일정·명단 출처: [soccer365](https://soccer365.net/competitions/637/)
