# GitHelper

Windows용 Git 작업 도우미입니다. Fork의 로컬 커밋을 feature 브랜치와 PR을 통해 `develop`에 반영하거나, 현재 커밋에서 브랜치를 분기하고 현재 브랜치를 `develop`에 직접 병합할 수 있습니다.

## 주요 기능

- `origin/develop` 이후 로컬 커밋 확인
- 최근 로컬 커밋 취소(파일 변경 내용 유지)
- 현재 HEAD에서 새 브랜치 생성 및 이동
- feature 브랜치 → PR → Rebase merge 자동화
- 현재 브랜치를 `develop`에 직접 병합 및 push
- 미커밋 파일 stash 보호
- GitHub 인증 자동 복구
- GitHub Release 기반 시작 시 업데이트 확인 및 자동 교체

## 실행

GitHub Releases에서 최신 `GitHelper.exe`를 내려받아 실행합니다.

## 빌드

PowerShell에서 `ps2exe` 모듈을 설치한 다음 실행합니다.

```powershell
Install-Module ps2exe -Scope CurrentUser
.\Build-Release.ps1 -Version 1.0.0
```

버전별 변경사항은 [CHANGELOG.md](CHANGELOG.md)를 참고하세요.
