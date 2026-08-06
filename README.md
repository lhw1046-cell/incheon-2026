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

1. Claude에게 **"인천 OO라운드 결과 업데이트해줘"** 라고 요청
   → 워크북·대시보드·`index.html`이 모두 갱신됩니다
2. **`publish.bat` 더블클릭**
   → 커밋 + 푸시. 1~2분 뒤 웹에 반영

---

## 참고

- 이 폴더는 OneDrive로 동기화됩니다. Git 저장소와 OneDrive를 함께 쓰면 드물게 충돌이
  날 수 있으니, 이상하면 `.git` 폴더를 OneDrive 동기화에서 제외하세요.
- 엑셀 파일이 열려 있으면 갱신 스크립트가 저장에 실패합니다. 갱신 전에 닫아주세요.
- 순위·경기 결과 출처: [soccer365](https://soccer365.net/competitions/637/)
