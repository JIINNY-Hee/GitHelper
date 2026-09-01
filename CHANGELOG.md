# ChangeLog

이 문서는 기존 CQI Git Helper v9 이후의 변경사항을 기록합니다. 제품명과 공개 버전 체계는 GitHelper v1.0.0부터 새로 시작합니다.

## GitHelper v1.0.1 - 2026-09-01

### 수정

- 현재 브랜치를 `develop`에 병합할 때 미커밋 파일이 있으면 작업을 차단하지 않고 자동 stash로 보호
- 병합과 push 완료 후 원래 브랜치로 돌아와 미커밋 파일 자동 복원
- 병합 실패 시에도 원래 브랜치 복귀와 stash 복원을 시도하도록 안전 처리
- 보호된 `develop` 브랜치에 직접 push해 `GH013` 오류가 발생하던 문제 수정
- 현재 브랜치 병합 기능을 GitHub PR 생성 및 PR merge 방식으로 변경
- 이전 직접 push 실패로 로컬 `develop`에 남을 수 있는 커밋을 병합 성공 후 `origin/develop` 기준으로 동기화

## GitHelper v1.0.0 - 2026-09-01

### 추가

- 현재 HEAD 커밋을 기준으로 새 브랜치를 만들고 바로 이동하는 기능
- 현재 브랜치를 `develop`에 직접 병합하고 원격에 push하는 기능
- 프로그램 시작 시 GitHub Release에서 새 버전을 확인하는 자동 업데이트 기능
- 새 버전 발견 시 Release ChangeLog를 보여주는 업데이트 확인창
- 프로그램 내부의 수동 `업데이트 확인` 버튼
- Git 브랜치와 병합을 표현한 전용 애플리케이션 아이콘
- GitHub Actions 기반 Release 빌드 및 배포 설정

### 변경

- 창 높이와 작업 버튼 영역을 확장
- 제품명을 CQI Git Helper에서 GitHelper로 변경
- 공개 버전을 v1.0.0으로 새로 시작

## v10.0.0 - 2026-09-01

### 추가

- 가장 최근 로컬 커밋을 커밋 이전 상태로 되돌리는 기능
- 되돌린 커밋의 파일 변경 내용을 작업 폴더에 유지하는 안전한 `mixed reset` 방식
- 커밋 되돌리기 전 확인창과 작업 로그

### 변경

- 임의의 중간 커밋 삭제 기능을 실제 사용 목적에 맞게 `최근 커밋 되돌리기`로 변경
- 수정 중인 파일이 있어도 최근 커밋을 되돌릴 수 있도록 개선
- 고해상도 및 Windows 화면 배율에서 글자가 선명하도록 Per-Monitor DPI 인식 적용
- `최근 커밋 되돌리기` 버튼의 문구가 잘리지 않도록 폭 확장

## v9.0.0 - 기준 버전

### 주요 기능

- `origin/develop` 이후의 Fork 커밋 검색 및 표시
- 추천 feature 브랜치 이름 자동 생성
- 미커밋 파일 stash 보호 및 작업 후 자동 복원
- feature 브랜치 생성과 커밋 cherry-pick
- 원격 feature 브랜치 push
- GitHub PR 생성 및 Rebase merge
- 병합 완료 후 로컬·원격 feature 브랜치 삭제 또는 유지
- GitHub CLI 로그인과 HTTPS 인증 자동 복구
- 한국어 커밋 메시지와 경로의 UTF-8 출력 지원
