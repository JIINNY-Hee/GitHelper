# ChangeLog

## GitHelper v1.0.4 - 2026-09-17

### 개선

- 업데이트 안내창의 크기를 제한하고 ChangeLog를 스크롤 가능한 영역으로 분리해 버튼이 화면 밖으로 밀려나지 않도록 개선
- GitHub Actions의 checkout을 Node.js 24 기반 버전으로 갱신

## GitHelper v1.0.3 - 2026-09-17

### 추가

- 프로그램 시작 시 Git 설치 여부를 자동으로 확인
- Git이 설치되어 있지 않으면 `winget`으로 Git for Windows를 자동 설치
- Git이 설치되어 있지만 PATH에 없으면 일반 설치 위치를 찾아 사용자 PATH에 자동 등록
- 설치 또는 PATH 등록 직후 프로그램을 재시작하지 않아도 Git을 사용할 수 있도록 현재 프로세스 환경 갱신
- GitHub CLI에 로그인된 계정이 여러 개이면 현재 저장소에 push 권한이 있는 계정을 자동 탐색
- 저장소에 사용할 수 있는 계정이 여러 개이면 작업 전에 계정 선택창 표시

### 개선

- Git 또는 `winget`을 사용할 수 없거나 자동 설치가 실패한 경우 원인과 수동 설치 주소 안내
- 잘못 활성화된 GitHub 계정으로 로그인과 PR 생성을 반복하지 않도록 저장소 권한 확인 후 계정 전환
- EXE 빌드 실패 시 이전 실행 파일을 정상 빌드 결과로 잘못 처리하지 않도록 빌드 검증 강화

## GitHelper v1.0.2 - 2026-09-01

### 추가

- `origin/develop` 이후 현재 브랜치에서 변경된 파일을 별도 창으로 확인
- Prefab, C#, 이미지, Material/Shader 파일을 확장자별로 분류해 표시
- 각 분류별 변경 파일 개수와 전체 경로 표시
- 여러 Git 저장소 경로를 즐겨찾기에 저장하고 콤보박스에서 즉시 전환
- 마지막 선택 저장소와 즐겨찾기 목록을 설정 파일에 자동 저장
- Windows 기본 테마와 시스템 버튼 색상을 사용하도록 UI 복원
- DPI 화면 배율에서도 문구가 잘리지 않도록 상단 업데이트 버튼 크기와 글꼴 조정
- 대규모 Unity 저장소 전환 시 시작 화면에서 fetch와 untracked 전체 검색을 생략해 응답 없음 현상 개선
- develop이 없는 저장소는 origin/main 또는 origin/master를 기준으로 조회
- 즐겨찾기 저장소의 origin 주소를 특정 프로젝트 주소로 강제 변경하지 않도록 수정

## GitHelper v1.0.1 - 2026-09-01

### 추가 및 개선

- 현재 브랜치를 `develop`에 병합할 때 미커밋 파일과 새 파일을 자동 stash로 보호
- 병합 완료 또는 실패 후 원래 브랜치로 돌아와 미커밋 파일 자동 복원
- 사용한 stash 항목을 정확히 찾아 자동 삭제
- 보호된 `develop` 브랜치에 직접 push하지 않고 GitHub PR을 생성해 병합하도록 변경
- 이미 열린 PR이 있으면 새로 만들지 않고 기존 PR 재사용
- merge commit을 금지한 저장소 정책에 맞게 Rebase merge 사용
- PR 병합 후 로컬 `develop`을 최신 `origin/develop` 기준으로 동기화
- 제품 파일을 `Source`와 `EXE` 폴더로 구분하고 GitHub Actions 빌드 경로 정리
- 브랜치 생성 후 직접 실행한 PR 병합에도 `로컬 + 원격 삭제`/`유지` 설정 적용

## GitHelper v1.0.0 - 2026-09-01

### 추가

- 현재 HEAD 커밋에서 새 브랜치를 만들고 바로 이동하는 기능
- 현재 브랜치를 `develop`에 반영하는 기능
- 프로그램 시작 시 GitHub Release에서 새 버전을 확인하는 자동 업데이트 기능
- 새 버전 발견 시 Release ChangeLog를 보여주는 업데이트 확인창
- 프로그램 상단의 수동 `업데이트 확인` 버튼
- Git 브랜치와 병합을 표현한 애플리케이션 아이콘
- GitHub Actions 기반 Release 빌드 및 배포 설정

### 변경

- 제품명을 CQI Git Helper에서 GitHelper로 변경
- 공개 버전을 v1.0.0으로 새로 시작
- 창 크기와 작업 버튼 배치 개선

## 내부 개발 버전 v10

- 가장 최근 로컬 커밋을 커밋 이전 상태로 되돌리는 기능
- 되돌린 커밋의 파일 변경 내용을 작업 폴더에 유지하는 `mixed reset` 방식
- 수정 중인 파일이 있어도 최근 커밋을 되돌릴 수 있도록 개선
- Per-Monitor DPI 인식을 적용해 Windows 화면 배율에서 글자 선명도 개선
- `최근 커밋 되돌리기` 버튼의 문구가 잘리지 않도록 폭 확장

## 내부 개발 버전 v9

- `origin/develop` 이후의 Fork 커밋 검색 및 표시
- 추천 feature 브랜치 이름 자동 생성
- 미커밋 파일 stash 보호 및 작업 후 자동 복원
- feature 브랜치 생성과 커밋 cherry-pick
- 원격 feature 브랜치 push
- GitHub PR 생성 및 Rebase merge
- 병합 완료 후 로컬·원격 feature 브랜치 삭제 또는 유지
- GitHub CLI 로그인과 HTTPS 인증 자동 복구
- 한국어 커밋 메시지와 경로의 UTF-8 출력 지원
