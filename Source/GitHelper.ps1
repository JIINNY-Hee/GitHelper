Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Git for Windows stores commit messages as UTF-8. Windows PowerShell 5.1,
# however, can decode native process output using the active console code page.
# Force UTF-8 so Korean commit subjects and paths are displayed correctly.
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [Console]::InputEncoding = $script:Utf8NoBom
    [Console]::OutputEncoding = $script:Utf8NoBom
} catch {}
$global:OutputEncoding = $script:Utf8NoBom
$env:LANG = 'ko_KR.UTF-8'
$env:LC_ALL = 'ko_KR.UTF-8'


$AppName = 'GitHelper v1.0.2'
$AppVersion = [version]'1.0.2'
$GitHubRepo = 'JIINNY-Hee/GitHelper'
$ConfigDir = Join-Path $env:APPDATA 'GitHelper'
$ConfigPath = Join-Path $ConfigDir 'config.json'
$LegacyConfigPath = Join-Path (Join-Path $env:APPDATA 'CQIGitHelper') 'config.json'
$ExpectedOriginSsh = 'git@github.com:loadcomplete-corp/cqi_client.git'
$ExpectedOriginHttps = 'https://github.com/loadcomplete-corp/cqi_client.git'

function Show-Error([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, $AppName, 'OK', 'Error') | Out-Null
}

function Show-Info([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, $AppName, 'OK', 'Information') | Out-Null
}

function Invoke-ProcessText {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [string]$WorkingDirectory
    )

    # PS2EXE's no-console host has no reliable console code page. Capture the
    # native process streams with an explicit encoding instead of letting
    # Windows PowerShell decode them through the (often ANSI) host encoding.
    function Quote-NativeArgument([string]$Value) {
        if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
        if ($Value -notmatch '[\s"]') { return $Value }

        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $slashes = 0
        foreach ($ch in $Value.ToCharArray()) {
            if ($ch -eq '\') {
                $slashes++
                continue
            }
            if ($ch -eq '"') {
                [void]$builder.Append((('\' * ($slashes * 2 + 1)) -join ''))
                [void]$builder.Append('"')
            } else {
                if ($slashes -gt 0) { [void]$builder.Append((('\' * $slashes) -join '')) }
                [void]$builder.Append($ch)
            }
            $slashes = 0
        }
        if ($slashes -gt 0) { [void]$builder.Append((('\' * ($slashes * 2)) -join '')) }
        [void]$builder.Append('"')
        return $builder.ToString()
    }

    $oldLocation = Get-Location
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-NativeArgument ([string]$_) }) -join ' ')
        if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $script:Utf8NoBom
        $startInfo.StandardErrorEncoding = $script:Utf8NoBom

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $process.Dispose()

        [pscustomobject]@{
            ExitCode = $exitCode
            StdOut = $stdout.TrimEnd()
            StdErr = $stderr.TrimEnd()
        }
    }
    finally {
        Set-Location $oldLocation
    }
}

$script:CurrentRepo = $null
$script:VisibleCommits = @()

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$GitArgs)
    if (-not $script:CurrentRepo -or -not (Test-Path -LiteralPath $script:CurrentRepo)) {
        throw 'Git 저장소 경로가 설정되지 않았습니다.'
    }

    # Apply only to this invocation; do not modify the user's global Git config.
    $effectiveArgs = @(
        '-c', 'i18n.logOutputEncoding=UTF-8',
        '-c', 'i18n.commitEncoding=UTF-8',
        '-c', 'core.quotepath=false'
    ) + $GitArgs

    return Invoke-ProcessText -FilePath 'git.exe' -Arguments $effectiveArgs -WorkingDirectory $script:CurrentRepo
}

function Invoke-Gh {
    param([Parameter(Mandatory=$true)][string[]]$GhArgs)
    if (-not $script:CurrentRepo -or -not (Test-Path -LiteralPath $script:CurrentRepo)) {
        throw 'Git 저장소 경로가 설정되지 않았습니다.'
    }
    return Invoke-ProcessText -FilePath 'gh.exe' -Arguments $GhArgs -WorkingDirectory $script:CurrentRepo
}

function Save-Config([string]$RepoPath) {
    if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
    @{ repoPath = $RepoPath } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Load-Config {
    $loadPath = if (Test-Path $ConfigPath) { $ConfigPath } elseif (Test-Path $LegacyConfigPath) { $LegacyConfigPath } else { $null }
    if ($loadPath) {
        try {
            return (Get-Content $loadPath -Raw | ConvertFrom-Json).repoPath
        } catch { return $null }
    }
    return $null
}

function Test-CommandAvailable([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-GitHubCli {
    if (Test-CommandAvailable 'gh') { return $true }

    $msg = "GitHub CLI(gh)가 설치되어 있지 않습니다.`r`n`r`nHTTPS 인증과 PR 자동 생성을 위해 GitHub CLI가 필요합니다.`r`n지금 winget으로 자동 설치할까요?"
    $answer = [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'YesNo', 'Question')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    if (-not (Test-CommandAvailable 'winget')) {
        Show-Error 'winget을 찾을 수 없어 GitHub CLI를 자동 설치할 수 없습니다.'
        return $false
    }

    Append-Log 'GitHub CLI를 설치합니다...'
    $install = Invoke-ProcessText -FilePath 'winget.exe' -Arguments @('install','--id','GitHub.cli','-e','--accept-package-agreements','--accept-source-agreements')
    if ($install.ExitCode -ne 0) {
        Show-Error "GitHub CLI 자동 설치에 실패했습니다.`r`n`r`n$($install.StdErr)"
        return $false
    }

    # Refresh PATH for the current PowerShell process after winget install.
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$machinePath;$userPath"
    return (Test-CommandAvailable 'gh')
}

function Ensure-GitHubHttpsAuth {
    if (-not (Ensure-GitHubCli)) { return $false }

    $auth = Invoke-Gh -GhArgs @('auth','status','--hostname','github.com')
    if ($auth.ExitCode -ne 0) {
        $msg = "GitHub 로그인이 필요합니다.`r`n`r`n[예]를 누르면 GitHub 로그인 창을 열고, 로그인 완료 후 자동으로 계속합니다."
        $answer = [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'YesNo', 'Question')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

        Append-Log 'GitHub 로그인 창을 엽니다...'
        $loginCommand = 'gh auth login --hostname github.com --git-protocol https --web'
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',$loginCommand) -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Show-Error 'GitHub 로그인이 완료되지 않았습니다.'
            return $false
        }

        $auth = Invoke-Gh -GhArgs @('auth','status','--hostname','github.com')
        if ($auth.ExitCode -ne 0) {
            Show-Error 'GitHub 로그인 상태를 확인하지 못했습니다.'
            return $false
        }
    }

    Append-Log 'GitHub 자격 증명을 Git에 연결합니다...'
    $setup = Invoke-Gh -GhArgs @('auth','setup-git')
    if ($setup.ExitCode -ne 0) {
        Show-Error "Git 자격 증명 연결에 실패했습니다.`r`n`r`n$($setup.StdErr)"
        return $false
    }
    return $true
}

function Switch-OriginToHttps {
    Append-Log "origin을 HTTPS 주소로 변경합니다: $ExpectedOriginHttps"
    $set = Invoke-Git -GitArgs @('remote','set-url','origin',$ExpectedOriginHttps)
    if ($set.ExitCode -ne 0) { throw "origin HTTPS 전환 실패:`r`n$($set.StdErr)" }
    return $ExpectedOriginHttps
}

function Normalize-Origin {
    $origin = Invoke-Git -GitArgs @('remote','get-url','origin')
    if ($origin.ExitCode -ne 0) { throw 'origin remote를 찾을 수 없습니다.' }

    if ($origin.StdOut -eq $ExpectedOriginSsh -or $origin.StdOut -eq $ExpectedOriginHttps) {
        return $origin.StdOut
    }

    # cq_idle -> cqi_client rename or any unexpected origin.
    $msg = "현재 origin:`r`n$($origin.StdOut)`r`n`r`n현재 저장소 주소로 자동 수정할까요?`r`n$ExpectedOriginHttps`r`n`r`nHTTPS를 사용하면 SSH 키 설정 없이 GitHub 로그인으로 인증할 수 있습니다."
    $answer = [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'YesNo', 'Question')
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        return Switch-OriginToHttps
    }
    return $origin.StdOut
}

function Fetch-OriginWithRepair {
    param([string]$OriginUrl)

    $fetch = Invoke-Git -GitArgs @('fetch','origin','--prune')
    if ($fetch.ExitCode -eq 0) { return $true }

    $err = $fetch.StdErr
    $isSshProblem = ($err -match 'Permission denied \(publickey\)') -or ($err -match 'Could not read from remote repository') -or ($OriginUrl -match '^git@github\.com:')
    $isHttpsAuthProblem = ($err -match 'Authentication failed') -or ($err -match 'could not read Username') -or ($err -match '403')

    if (-not ($isSshProblem -or $isHttpsAuthProblem)) {
        throw "origin fetch 실패:`r`n$err"
    }

    $msg = "GitHub 인증에 실패했습니다.`r`n`r`n$err`r`n`r`n프로그램이 다음 작업을 자동으로 처리할 수 있습니다:`r`n- origin을 HTTPS로 전환`r`n- GitHub 로그인 확인/실행`r`n- Git 자격 증명 연결`r`n- fetch 재시도`r`n`r`n자동 복구할까요?"
    $answer = [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'YesNo', 'Question')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        throw "origin fetch 실패:`r`n$err"
    }

    if (-not (Ensure-GitHubHttpsAuth)) {
        throw 'GitHub 인증 자동 복구가 완료되지 않았습니다.'
    }

    [void](Switch-OriginToHttps)
    Append-Log 'HTTPS 인증으로 origin fetch를 다시 시도합니다...'
    $retry = Invoke-Git -GitArgs @('fetch','origin','--prune')
    if ($retry.ExitCode -ne 0) {
        throw "HTTPS 전환 후에도 origin fetch에 실패했습니다:`r`n$($retry.StdErr)"
    }
    Append-Log 'GitHub 인증 복구 및 fetch 성공.'
    return $true
}

function Get-RepoState([string]$Repo) {
    if (-not $Repo -or -not (Test-Path -LiteralPath $Repo)) { throw '선택한 저장소 폴더가 존재하지 않습니다.' }
    $script:CurrentRepo = (Resolve-Path -LiteralPath $Repo).Path
    $inside = Invoke-Git -GitArgs @('rev-parse','--is-inside-work-tree')
    if ($inside.ExitCode -ne 0 -or $inside.StdOut -ne 'true') { throw '선택한 폴더가 Git 저장소가 아닙니다.' }

    $root = Invoke-Git -GitArgs @('rev-parse','--show-toplevel')
    if ($root.ExitCode -ne 0) { throw 'Git 저장소 루트를 확인하지 못했습니다.' }
    $Repo = $root.StdOut
    $script:CurrentRepo = $Repo

    $origin = Normalize-Origin
    [void](Fetch-OriginWithRepair -OriginUrl $origin)
    $origin = (Invoke-Git -GitArgs @('remote','get-url','origin')).StdOut

    $base = Invoke-Git -GitArgs @('rev-parse','--verify','origin/develop')
    if ($base.ExitCode -ne 0) { throw 'origin/develop 브랜치를 찾을 수 없습니다.' }

    $branch = Invoke-Git -GitArgs @('branch','--show-current')
    $head = Invoke-Git -GitArgs @('rev-parse','HEAD')
    $status = Invoke-Git -GitArgs @('status','--porcelain=v1')
    $log = Invoke-Git -GitArgs @('log','--reverse','--encoding=UTF-8','--format=%H%x09%h%x09%s','origin/develop..HEAD')

    $commits = @()
    if ($log.ExitCode -eq 0 -and $log.StdOut) {
        foreach ($line in ($log.StdOut -split "`r?`n")) {
            if (-not $line.Trim()) { continue }
            $parts = $line -split "`t",3
            if ($parts.Count -eq 3) {
                $commits += [pscustomobject]@{ Full=$parts[0]; Short=$parts[1]; Subject=$parts[2] }
            }
        }
    }

    [pscustomobject]@{
        Repo = $Repo
        Origin = $origin
        Branch = $branch.StdOut
        Head = $head.StdOut
        Dirty = [bool]$status.StdOut
        StatusText = $status.StdOut
        Commits = $commits
    }
}

function Make-BranchSuggestion($Commits) {
    if (-not $Commits -or $Commits.Count -eq 0) { return 'feat/fork-change' }

    $commit = $Commits[-1]
    $subject = [string]$commit.Subject
    $shortSha = [string]$commit.Short

    # Preserve a Conventional Commit type when present.
    $prefix = 'feat'
    $body = $subject
    if ($subject -match '^\s*(feat|fix|refactor|perf|test|docs|build|ci|chore|style)(?:\([^)]+\))?\s*:\s*(.+)$') {
        $prefix = $matches[1].ToLowerInvariant()
        $body = $matches[2]
    }

    # Common project/dev vocabulary. Longer phrases are replaced first.
    # The goal is a short, readable English branch name, not a literal translation.
    $phrases = [ordered]@{
        '오프라인 보상'='offline reward'
        '도메인 카드'='domain card'
        '사슬 채찍'='chain whip'
        '버텍스 디스플레이스먼트'='vertex displacement'
        '알파 클리핑'='alpha clipping'
        '쉐이더 그래프'='shader graph'
        '셰이더 그래프'='shader graph'
        '어드레서블'='addressables'
        '퍼포먼스 테스트'='performance test'
        '성능 테스트'='performance test'
    }

    $words = [ordered]@{
        '검'='sword'; '칼'='sword'
        '사슬'='chain'; '체인'='chain'; '채찍'='whip'
        '이펙트'='effect'; '연출'='vfx'; '효과'='effect'
        '파티클'='particle'; '빔'='beam'; '그라데이션'='gradient'
        '쉐이더'='shader'; '셰이더'='shader'; '머티리얼'='material'; '메테리얼'='material'
        '버텍스'='vertex'; '디스플레이스먼트'='displacement'; '마스크'='mask'
        '텍스처'='texture'; '스프라이트'='sprite'; '이미지'='image'
        '메쉬'='mesh'; '노말'='normal'; '프리팹'='prefab'
        '애니메이션'='animation'; '캐릭터'='character'; '몬스터'='monster'; '보스'='boss'
        '스킬'='skill'; '공격'='attack'; '피격'='hit'; '투사체'='projectile'
        'UI'='ui'; '아이콘'='icon'; '버튼'='button'; '팝업'='popup'; '배경'='background'
        '도메인'='domain'; '카드'='card'
        '보상'='reward'; '오프라인'='offline'
        '세이브'='save'; '저장'='save'; '로드'='load'; '데이터'='data'
        '사운드'='sound'; '오디오'='audio'
        '버그'='bug'; '오류'='error'; '에러'='error'
        '설정'='config'; '시스템'='system'; '로직'='logic'
        '성능'='performance'; '최적화'='optimize'; '리팩토링'='refactor'
        '테스트'='test'; '빌드'='build'
        '추가'='add'; '수정'='fix'; '변경'='update'; '개선'='improve'
        '삭제'='remove'; '제거'='remove'; '정리'='cleanup'; '갱신'='update'
        '적용'='apply'; '지원'='support'; '처리'='handle'
    }

    $translated = $body
    foreach ($key in $phrases.Keys) {
        $translated = $translated -replace [regex]::Escape($key), (' ' + $phrases[$key] + ' ')
    }
    foreach ($key in $words.Keys) {
        $translated = $translated -replace [regex]::Escape($key), (' ' + $words[$key] + ' ')
    }

    # Keep already-English identifiers, and discard Korean that could not be mapped.
    $tokens = @()
    foreach ($m in [regex]::Matches($translated.ToLowerInvariant(), '[a-z0-9]+')) {
        $w = $m.Value
        if ($w.Length -eq 1 -and $w -notmatch '^\d$') { continue }
        $tokens += $w
    }

    # Words such as add/fix/update are usually redundant when the branch prefix
    # already describes the operation. Prefer nouns and domain terms.
    $noise = @('add','added','fix','fixed','update','updated','change','changed','apply','handle','support')
    $meaningful = @()
    foreach ($t in $tokens) {
        if ($noise -contains $t) { continue }
        if ($meaningful -notcontains $t) { $meaningful += $t }
        if ($meaningful.Count -ge 4) { break }
    }

    # If filtering removed everything, use up to four raw English tokens.
    if ($meaningful.Count -eq 0) {
        foreach ($t in $tokens) {
            if ($meaningful -notcontains $t) { $meaningful += $t }
            if ($meaningful.Count -ge 4) { break }
        }
    }

    if ($meaningful.Count -eq 0) {
        return "$prefix/commit-$shortSha"
    }

    $slug = ($meaningful -join '-')
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0,48).Trim('-')
    }

    return "$prefix/$slug"
}

function Append-Log([string]$Text) {
    $txtLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Text`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy([bool]$Busy) {
    $btnRefresh.Enabled = -not $Busy
    $btnBrowse.Enabled = -not $Busy
    $btnRun.Enabled = -not $Busy
    $btnDeleteCommit.Enabled = (-not $Busy) -and ($script:VisibleCommits.Count -gt 0)
    $btnCreateBranch.Enabled = -not $Busy
    $btnMergeDevelop.Enabled = -not $Busy
    $btnUpdate.Enabled = -not $Busy
    $txtRepo.Enabled = -not $Busy
    $txtBranch.Enabled = -not $Busy
    $radioDelete.Enabled = -not $Busy
    $radioKeep.Enabled = -not $Busy
    $form.UseWaitCursor = $Busy
    [System.Windows.Forms.Application]::DoEvents()
}

function New-BranchAtHead {
    $repo = $txtRepo.Text.Trim()
    $branchName = $txtBranch.Text.Trim()
    if (-not $repo -or -not (Test-Path -LiteralPath $repo)) { Show-Error '올바른 저장소 폴더를 선택해 주세요.'; return }
    if (-not $branchName -or $branchName -notmatch '^[A-Za-z0-9._/-]+$') { Show-Error '새 브랜치 이름을 입력해 주세요.'; return }

    Set-Busy $true
    try {
        $state = Get-RepoState $repo
        $exists = Invoke-Git -GitArgs @('show-ref','--verify','--quiet',"refs/heads/$branchName")
        if ($exists.ExitCode -eq 0) { throw "로컬 브랜치 '$branchName'가 이미 존재합니다." }

        $answer = [System.Windows.Forms.MessageBox]::Show("현재 커밋에서 새 브랜치를 만들고 이동합니다.`r`n`r`n현재: $($state.Branch)`r`n새 브랜치: $branchName`r`n커밋: $($state.Head.Substring(0,8))`r`n`r`n수정 중인 파일은 그대로 유지됩니다.", $AppName, 'YesNo', 'Question')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Append-Log "현재 커밋에서 브랜치 생성: $branchName"
        $create = Invoke-Git -GitArgs @('switch','-c',$branchName)
        if ($create.ExitCode -ne 0) { throw "브랜치 생성 실패:`r`n$($create.StdErr)" }
        Append-Log "브랜치 생성 및 이동 완료: $branchName"
        Show-Info "새 브랜치를 만들었습니다.`r`n`r`n$branchName"
    }
    catch { Append-Log "브랜치 생성 중단: $($_.Exception.Message)"; Show-Error $_.Exception.Message }
    finally { Set-Busy $false; Refresh-View }
}

function Merge-CurrentBranchToDevelop {
    $repo = $txtRepo.Text.Trim()
    if (-not $repo -or -not (Test-Path -LiteralPath $repo)) { Show-Error '올바른 저장소 폴더를 선택해 주세요.'; return }

    Set-Busy $true
    $sourceBranch = $null
    $stashHash = $null
    try {
        $state = Get-RepoState $repo
        $sourceBranch = $state.Branch
        if (-not $sourceBranch) { throw '분리된 HEAD 상태에서는 병합할 수 없습니다.' }
        if ($sourceBranch -eq 'develop') { throw '현재 브랜치가 이미 develop입니다.' }

        $dirtyNotice = if ($state.Dirty) { "`r`n`r`n미커밋 파일은 자동으로 임시 보관한 뒤 원래 브랜치에 복원합니다." } else { '' }
        $answer = [System.Windows.Forms.MessageBox]::Show("현재 브랜치로 develop 대상 PR을 만들고 병합합니다.`r`n`r`n$sourceBranch  →  develop$dirtyNotice`r`n`r`n계속할까요?", $AppName, 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        if ($state.Dirty) {
            Append-Log '미커밋 파일을 안전하게 임시 보관합니다...'
            $stash = Invoke-Git -GitArgs @('stash','push','-u','-m',"GitHelper merge $(Get-Date -Format s)")
            if ($stash.ExitCode -ne 0) { throw "stash 실패:`r`n$($stash.StdErr)" }
            $stashRef = Invoke-Git -GitArgs @('rev-parse','stash@{0}')
            if ($stashRef.ExitCode -ne 0) { throw '생성한 stash를 확인하지 못했습니다.' }
            $stashHash = $stashRef.StdOut
            Append-Log "미커밋 파일 보관 완료: $($stashHash.Substring(0,8))"
        }

        Append-Log "현재 브랜치를 origin에 push합니다: $sourceBranch"
        $push = Invoke-Git -GitArgs @('push','-u','origin',$sourceBranch)
        if ($push.ExitCode -ne 0) { throw "현재 브랜치 push 실패:`r`n$($push.StdErr)" }

        if (-not (Ensure-GitHubHttpsAuth)) { throw 'GitHub 인증을 완료하지 못했습니다.' }
        $title = if ($state.Commits.Count -gt 0) { $state.Commits[-1].Subject } else { "Merge $sourceBranch into develop" }
        $body = "GitHelper에서 현재 브랜치 '$sourceBranch'를 develop에 병합하기 위해 생성한 PR입니다."

        Append-Log 'develop 대상 PR을 생성합니다...'
        $pr = Invoke-Gh -GhArgs @('pr','create','--base','develop','--head',$sourceBranch,'--title',$title,'--body',$body)
        if ($pr.ExitCode -eq 0) {
            $prUrl = ($pr.StdOut -split "`r?`n" | Select-Object -Last 1).Trim()
        } else {
            $existing = Invoke-Gh -GhArgs @('pr','view',$sourceBranch,'--json','url','--jq','.url')
            if ($existing.ExitCode -ne 0) { throw "PR 생성 실패:`r`n$($pr.StdErr)" }
            $prUrl = $existing.StdOut.Trim()
            Append-Log "기존 PR을 사용합니다: $prUrl"
        }

        Append-Log 'PR을 merge 합니다...'
        $merge = Invoke-Gh -GhArgs @('pr','merge',$sourceBranch,'--merge')
        if ($merge.ExitCode -ne 0) { throw "PR 병합이 완료되지 않았습니다.`r`n리뷰나 CI 조건을 확인해 주세요.`r`n`r`nPR: $prUrl`r`n`r`n$($merge.StdErr)" }

        Append-Log '병합된 origin/develop을 동기화합니다...'
        $fetch = Invoke-Git -GitArgs @('fetch','origin','--prune')
        if ($fetch.ExitCode -ne 0) { throw "병합 후 fetch 실패:`r`n$($fetch.StdErr)" }
        $checkout = Invoke-Git -GitArgs @('switch','develop')
        if ($checkout.ExitCode -ne 0) { throw "develop 이동 실패:`r`n$($checkout.StdErr)" }
        $sync = Invoke-Git -GitArgs @('reset','--hard','origin/develop')
        if ($sync.ExitCode -ne 0) { throw "로컬 develop 동기화 실패:`r`n$($sync.StdErr)" }

        $back = Invoke-Git -GitArgs @('switch',$sourceBranch)
        if ($back.ExitCode -ne 0) { throw "원래 브랜치 '$sourceBranch' 복귀 실패:`r`n$($back.StdErr)" }
        if ($stashHash) {
            Restore-Stash $stashHash
            $stashHash = $null
        }
        Append-Log '현재 브랜치를 develop에 병합했습니다.'
        Show-Info "$sourceBranch 브랜치를 PR을 통해 develop에 병합했습니다.`r`n`r`n$prUrl"
    }
    catch {
        Append-Log "develop 병합 중단: $($_.Exception.Message)"
        if ($sourceBranch) {
            $current = Invoke-Git -GitArgs @('branch','--show-current')
            if ($current.ExitCode -eq 0 -and $current.StdOut -ne $sourceBranch) { [void](Invoke-Git -GitArgs @('switch',$sourceBranch)) }
        }
        if ($stashHash) {
            Restore-Stash $stashHash
            $stashHash = $null
        }
        Show-Error $_.Exception.Message
    }
    finally { Set-Busy $false; Refresh-View }
}

function Check-ForUpdate([bool]$Manual = $false) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{ 'User-Agent' = 'GitHelper' }
        $release = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" -TimeoutSec 7
        $latestText = ([string]$release.tag_name).TrimStart('v')
        $latest = [version]$latestText
        if ($latest -le $AppVersion) {
            if ($Manual) { Show-Info "현재 최신 버전입니다. (v$AppVersion)" }
            return
        }

        $changeLog = if ($release.body) { [string]$release.body } else { '변경 내역이 제공되지 않았습니다.' }
        $answer = [System.Windows.Forms.MessageBox]::Show("새 버전 v$latest이 있습니다. (현재 v$AppVersion)`r`n`r`n[ChangeLog]`r`n$changeLog`r`n`r`n지금 업데이트할까요?", 'GitHelper 업데이트', 'YesNo', 'Information')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $asset = @($release.assets | Where-Object { $_.name -eq 'GitHelper.exe' } | Select-Object -First 1)
        if ($asset.Count -eq 0) { throw 'Release에서 GitHelper.exe 파일을 찾을 수 없습니다.' }
        $currentExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([IO.Path]::GetFileName($currentExe) -ieq 'powershell.exe') { throw '스크립트 실행 중에는 자동 업데이트할 수 없습니다. EXE에서 실행해 주세요.' }

        $download = Join-Path $env:TEMP "GitHelper-$latest.exe"
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $asset.browser_download_url -OutFile $download -TimeoutSec 60
        $updater = Join-Path $env:TEMP 'GitHelper-Updater.ps1'
        $updaterText = @"
param([int]`$ProcessId, [string]`$Source, [string]`$Target)
Wait-Process -Id `$ProcessId -ErrorAction SilentlyContinue
Copy-Item -LiteralPath `$Source -Destination `$Target -Force
Start-Process -FilePath `$Target
Remove-Item -LiteralPath `$Source -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath `$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
"@
        Set-Content -LiteralPath $updater -Value $updaterText -Encoding UTF8
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$updater,'-ProcessId',$PID,'-Source',$download,'-Target',$currentExe) -WindowStyle Hidden
        $form.Close()
    }
    catch {
        if ($Manual) { Show-Error "업데이트 확인에 실패했습니다.`r`n`r`n$($_.Exception.Message)" }
        else { Append-Log "업데이트 확인 생략: $($_.Exception.Message)" }
    }
}

function Undo-LastCommit {
    if ($script:VisibleCommits.Count -eq 0) {
        Show-Info '되돌릴 로컬 커밋이 없습니다.'
        return
    }

    $commit = $script:VisibleCommits[-1]
    $repo = $txtRepo.Text.Trim()
    $message = "가장 최근 로컬 커밋을 커밋 이전 상태로 되돌립니다.`r`n`r`n$($commit.Short)  $($commit.Subject)`r`n`r`n커밋 기록만 취소되며 파일 변경 내용은 작업 폴더에 그대로 남습니다. 원격 저장소에는 아무 작업도 하지 않습니다.`r`n`r`n계속할까요?"
    $answer = [System.Windows.Forms.MessageBox]::Show($message, $AppName, 'YesNo', 'Warning')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Set-Busy $true
    try {
        $state = Get-RepoState $repo
        if ($state.Commits.Count -eq 0 -or $state.Head -ne $commit.Full) { throw '가장 최근 커밋이 변경되었습니다. 새로고침 후 다시 시도해 주세요.' }
        if (-not $state.Branch) { throw '분리된 HEAD 상태에서는 커밋을 되돌릴 수 없습니다.' }

        Append-Log "최근 커밋 되돌리기: $($commit.Short) $($commit.Subject)"
        $reset = Invoke-Git -GitArgs @('reset','--mixed','HEAD^')
        if ($reset.ExitCode -ne 0) { throw "커밋을 되돌리지 못했습니다:`r`n$($reset.StdErr)" }

        Append-Log '최근 커밋을 되돌렸습니다. 파일 변경 내용은 작업 폴더에 유지됩니다.'
        Show-Info "커밋 이전 상태로 되돌렸습니다.`r`n파일 변경 내용은 그대로 남아 있습니다.`r`n`r`n$($commit.Short)  $($commit.Subject)"
    }
    catch {
        Append-Log "커밋 삭제 중단: $($_.Exception.Message)"
        Show-Error $_.Exception.Message
    }
    finally {
        Set-Busy $false
        Refresh-View
    }
}

function Restore-Stash([string]$StashHash) {
    if (-not $StashHash) { return }
    Append-Log '작업 중이던 미커밋 파일을 복원합니다...'
    $apply = Invoke-Git -GitArgs @('stash','apply','--index',$StashHash)
    if ($apply.ExitCode -ne 0) {
        Append-Log "주의: stash 자동 복원 중 충돌이 발생했습니다. stash는 삭제하지 않았습니다."
        Show-Error "Git 작업은 끝났지만 작업 파일 자동 복원 중 충돌이 발생했습니다.`r`n`r`n보존된 stash: $StashHash`r`nFork에서 충돌 상태를 확인해 주세요."
        return
    }
    $stashList = Invoke-Git -GitArgs @('stash','list','--format=%gd%x09%H')
    $stashRef = $null
    if ($stashList.ExitCode -eq 0 -and $stashList.StdOut) {
        foreach ($line in ($stashList.StdOut -split "`r?`n")) {
            $parts = $line -split "`t",2
            if ($parts.Count -eq 2 -and $parts[1] -eq $StashHash) { $stashRef = $parts[0]; break }
        }
    }
    if ($stashRef) {
        $drop = Invoke-Git -GitArgs @('stash','drop',$stashRef)
        if ($drop.ExitCode -ne 0) { Append-Log 'stash 복원은 성공했지만 자동 삭제는 실패했습니다.' }
        else { Append-Log '미커밋 작업 파일 복원 완료.' }
    } else {
        Append-Log '미커밋 작업 파일은 복원됐지만 stash 위치를 찾지 못해 보관 항목을 유지합니다.'
    }
}

function Run-Workflow {
    $repo = $txtRepo.Text.Trim()
    $feature = $txtBranch.Text.Trim()
    if (-not $repo -or -not (Test-Path $repo)) { Show-Error '올바른 저장소 폴더를 선택해 주세요.'; return }
    if (-not $feature -or $feature -notmatch '^[A-Za-z0-9._/-]+$') { Show-Error '브랜치 이름이 비어 있거나 사용할 수 없는 문자가 있습니다.'; return }

    Set-Busy $true
    $stashHash = $null
    $originalBranch = $null
    $originalHead = $null
    $featurePushed = $false
    $prUrl = $null

    try {
        Append-Log '저장소 상태를 다시 확인합니다...'
        $state = Get-RepoState $repo
        $repo = $state.Repo
        $txtRepo.Text = $repo
        Save-Config $repo
        $originalBranch = $state.Branch
        $originalHead = $state.Head

        if ($state.Commits.Count -eq 0) { throw 'origin/develop 이후 처리할 커밋이 없습니다.' }

        $existsLocal = Invoke-Git -GitArgs @('show-ref','--verify','--quiet',"refs/heads/$feature")
        if ($existsLocal.ExitCode -eq 0) { throw "로컬 브랜치 '$feature'가 이미 존재합니다." }
        $existsRemote = Invoke-Git -GitArgs @('ls-remote','--exit-code','--heads','origin',$feature)
        if ($existsRemote.ExitCode -eq 0) { throw "원격 브랜치 '$feature'가 이미 존재합니다." }

        if ($state.Dirty) {
            Append-Log '미커밋 파일 감지. 안전하게 임시 보관합니다...'
            $stash = Invoke-Git -GitArgs @('stash','push','-u','-m',"GitHelper $(Get-Date -Format s)")
            if ($stash.ExitCode -ne 0) { throw "stash 실패:`r`n$($stash.StdErr)" }
            $stashRef = Invoke-Git -GitArgs @('rev-parse','stash@{0}')
            if ($stashRef.ExitCode -ne 0) { throw '생성한 stash를 확인하지 못했습니다.' }
            $stashHash = $stashRef.StdOut
            Append-Log "미커밋 파일 보관 완료: $($stashHash.Substring(0,8))"
        }

        Append-Log "origin/develop 기준 feature 생성: $feature"
        $checkout = Invoke-Git -GitArgs @('checkout','-b',$feature,'origin/develop')
        if ($checkout.ExitCode -ne 0) { throw "feature 브랜치 생성 실패:`r`n$($checkout.StdErr)" }

        foreach ($commit in $state.Commits) {
            Append-Log "커밋 적용: $($commit.Short) $($commit.Subject)"
            $cp = Invoke-Git -GitArgs @('cherry-pick',$commit.Full)
            if ($cp.ExitCode -ne 0) {
                [void](Invoke-Git -GitArgs @('cherry-pick','--abort'))
                throw "cherry-pick 충돌이 발생했습니다.`r`n커밋: $($commit.Short) $($commit.Subject)`r`n`r`n자동 처리를 중단했습니다."
            }
        }

        Append-Log 'feature 브랜치를 origin에 push 합니다...'
        $push = Invoke-Git -GitArgs @('push','-u','origin',$feature)
        if ($push.ExitCode -ne 0) {
            $pushErr = $push.StdErr
            $authRelated = ($pushErr -match 'Permission denied \(publickey\)') -or ($pushErr -match 'Authentication failed') -or ($pushErr -match 'Could not read from remote repository') -or ($pushErr -match 'could not read Username')
            if ($authRelated) {
                Append-Log 'push 인증 오류 감지. HTTPS 인증 자동 복구를 시도합니다...'
                if (-not (Ensure-GitHubHttpsAuth)) { throw "feature push 인증 실패:`r`n$pushErr" }
                [void](Switch-OriginToHttps)
                $push = Invoke-Git -GitArgs @('push','-u','origin',$feature)
            }
            if ($push.ExitCode -ne 0) { throw "feature push 실패:`r`n$($push.StdErr)" }
        }
        $featurePushed = $true

        if (-not (Ensure-GitHubHttpsAuth)) { throw 'GitHub 인증을 완료하지 못했습니다. feature push까지는 완료했습니다.' }

        $title = $state.Commits[-1].Subject
        if ($state.Commits.Count -gt 1) { $title = "$title 외 $($state.Commits.Count - 1)건" }
        $body = "GitHelper에서 Fork 커밋 $($state.Commits.Count)개를 추적해 생성한 PR입니다."

        Append-Log 'develop 대상 PR을 생성합니다...'
        $pr = Invoke-Gh -GhArgs @('pr','create','--base','develop','--head',$feature,'--title',$title,'--body',$body)
        if ($pr.ExitCode -ne 0) { throw "PR 생성 실패:`r`n$($pr.StdErr)" }
        $prUrl = ($pr.StdOut -split "`r?`n" | Select-Object -Last 1).Trim()
        Append-Log "PR 생성 완료: $prUrl"

        Append-Log 'PR을 Rebase merge 합니다...'
        $merge = Invoke-Gh -GhArgs @('pr','merge',$feature,'--rebase')
        if ($merge.ExitCode -ne 0) {
            throw "PR 자동 머지가 완료되지 않았습니다.`r`nCI/리뷰 승인 조건을 확인해 주세요.`r`n`r`nPR: $prUrl`r`n`r`nfeature 브랜치는 유지됩니다."
        }
        Append-Log 'Rebase merge 완료.'

        Append-Log '최신 develop을 동기화합니다...'
        $fetch2 = Invoke-Git -GitArgs @('fetch','origin','--prune')
        if ($fetch2.ExitCode -ne 0) { throw "merge 후 fetch 실패:`r`n$($fetch2.StdErr)" }

        if ($originalBranch -eq 'develop') {
            $coDev = Invoke-Git -GitArgs @('checkout','develop')
            if ($coDev.ExitCode -ne 0) { throw "develop checkout 실패:`r`n$($coDev.StdErr)" }
            $reset = Invoke-Git -GitArgs @('reset','--hard','origin/develop')
            if ($reset.ExitCode -ne 0) { throw "develop 동기화 실패:`r`n$($reset.StdErr)" }
        } else {
            $back = Invoke-Git -GitArgs @('checkout',$originalBranch)
            if ($back.ExitCode -ne 0) { throw "원래 브랜치 '$originalBranch' 복귀 실패:`r`n$($back.StdErr)" }
        }

        Restore-Stash $stashHash
        $stashHash = $null

        if ($radioDelete.Checked) {
            Append-Log 'feature 브랜치를 정리합니다...'
            if ((Invoke-Git -GitArgs @('branch','--show-current')).StdOut -eq $feature) {
                [void](Invoke-Git -GitArgs @('checkout','develop'))
            }
            $delLocal = Invoke-Git -GitArgs @('branch','-D',$feature)
            if ($delLocal.ExitCode -eq 0) { Append-Log '로컬 feature 삭제 완료.' }
            else { Append-Log '로컬 feature 삭제 실패 또는 이미 없음.' }

            $delRemote = Invoke-Git -GitArgs @('push','origin','--delete',$feature)
            if ($delRemote.ExitCode -eq 0) { Append-Log '원격 feature 삭제 완료.' }
            else { Append-Log '원격 feature 삭제 실패 또는 이미 GitHub에서 삭제됨.' }
        } else {
            Append-Log 'feature 브랜치를 유지합니다.'
        }

        Append-Log '모든 작업이 완료되었습니다.'
        Show-Info "완료되었습니다.`r`n`r`nPR: $prUrl`r`n브랜치: $feature"
        Refresh-View
    }
    catch {
        $message = $_.Exception.Message
        Append-Log "중단: $message"

        if ($originalBranch) {
            $current = Invoke-Git -GitArgs @('branch','--show-current')
            if ($current.ExitCode -eq 0 -and $current.StdOut -and $current.StdOut -ne $originalBranch) {
                [void](Invoke-Git -GitArgs @('checkout',$originalBranch))
            }
        }

        if ($stashHash) {
            Restore-Stash $stashHash
            $stashHash = $null
        }

        Show-Error $message
    }
    finally {
        Set-Busy $false
    }
}

function Refresh-View {
    $repo = $txtRepo.Text.Trim()
    if (-not $repo -or -not (Test-Path $repo)) {
        $lblStatus.Text = '저장소를 선택해 주세요.'
        $listCommits.Items.Clear()
        $script:VisibleCommits = @()
        $btnDeleteCommit.Enabled = $false
        $btnRun.Enabled = $false
        $btnCreateBranch.Enabled = $false
        $btnMergeDevelop.Enabled = $false
        return
    }

    try {
        $state = Get-RepoState $repo
        $txtRepo.Text = $state.Repo
        Save-Config $state.Repo
        $dirtyText = if ($state.Dirty) { '미커밋 파일 있음 (자동 보호)' } else { '작업 폴더 깨끗함' }
        $lblStatus.Text = "브랜치: $($state.Branch)    |    Origin: $($state.Origin)    |    $dirtyText"
        $listCommits.Items.Clear()
        $script:VisibleCommits = @($state.Commits)
        foreach ($c in $state.Commits) {
            [void]$listCommits.Items.Add("$($c.Short)   $($c.Subject)")
        }
        if ($state.Commits.Count -gt 0) {
            $txtBranch.Text = Make-BranchSuggestion $state.Commits
            $btnRun.Enabled = $true
            $btnDeleteCommit.Enabled = $true
            $lblCommitCount.Text = "처리할 커밋: $($state.Commits.Count)개"
        } else {
            $btnRun.Enabled = $false
            $btnDeleteCommit.Enabled = $false
            $lblCommitCount.Text = '처리할 커밋: 0개'
        }
        $btnCreateBranch.Enabled = $true
        $btnMergeDevelop.Enabled = ($state.Branch -and $state.Branch -ne 'develop')
    }
    catch {
        $lblStatus.Text = "확인 실패: $($_.Exception.Message)"
        $listCommits.Items.Clear()
        $script:VisibleCommits = @()
        $btnDeleteCommit.Enabled = $false
        $btnRun.Enabled = $false
        $btnCreateBranch.Enabled = $false
        $btnMergeDevelop.Enabled = $false
    }
}

# ---------------- UI ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = $AppName
$form.Size = New-Object System.Drawing.Size(860,820)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(860,820)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font('Malgun Gothic',10,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point)
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {}

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'GitHelper v1.0.2'
$lblTitle.Font = New-Object System.Drawing.Font('Malgun Gothic',18,[System.Drawing.FontStyle]::Bold)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(24,18)
$form.Controls.Add($lblTitle)

$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = 'Fork에서 만든 커밋을 feature 브랜치 → PR → develop(Rebase merge) 흐름으로 안전하게 반영합니다.'
$lblDesc.AutoSize = $true
$lblDesc.Location = New-Object System.Drawing.Point(26,55)
$form.Controls.Add($lblDesc)

$lblRepo = New-Object System.Windows.Forms.Label
$lblRepo.Text = 'Repository'
$lblRepo.AutoSize = $true
$lblRepo.Location = New-Object System.Drawing.Point(26,96)
$form.Controls.Add($lblRepo)

$txtRepo = New-Object System.Windows.Forms.TextBox
$txtRepo.Location = New-Object System.Drawing.Point(28,120)
$txtRepo.Size = New-Object System.Drawing.Size(650,28)
$form.Controls.Add($txtRepo)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '변경...'
$btnBrowse.Location = New-Object System.Drawing.Point(690,118)
$btnBrowse.Size = New-Object System.Drawing.Size(120,32)
$form.Controls.Add($btnBrowse)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = '새로고침'
$btnRefresh.Location = New-Object System.Drawing.Point(690,158)
$btnRefresh.Size = New-Object System.Drawing.Size(120,32)
$form.Controls.Add($btnRefresh)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '저장소 확인 중...'
$lblStatus.AutoSize = $false
$lblStatus.Size = New-Object System.Drawing.Size(650,45)
$lblStatus.Location = New-Object System.Drawing.Point(28,158)
$form.Controls.Add($lblStatus)

$lblCommitCount = New-Object System.Windows.Forms.Label
$lblCommitCount.Text = '처리할 커밋'
$lblCommitCount.AutoSize = $true
$lblCommitCount.Font = New-Object System.Drawing.Font('Malgun Gothic',10,[System.Drawing.FontStyle]::Bold)
$lblCommitCount.Location = New-Object System.Drawing.Point(28,215)
$form.Controls.Add($lblCommitCount)

$listCommits = New-Object System.Windows.Forms.ListBox
$listCommits.Location = New-Object System.Drawing.Point(28,242)
$listCommits.Size = New-Object System.Drawing.Size(782,120)
$form.Controls.Add($listCommits)

$btnDeleteCommit = New-Object System.Windows.Forms.Button
$btnDeleteCommit.Text = '최근 커밋 되돌리기'
$btnDeleteCommit.Location = New-Object System.Drawing.Point(610,204)
$btnDeleteCommit.Size = New-Object System.Drawing.Size(200,32)
$btnDeleteCommit.Enabled = $false
$form.Controls.Add($btnDeleteCommit)

$lblBranch = New-Object System.Windows.Forms.Label
$lblBranch.Text = 'Feature branch 이름'
$lblBranch.AutoSize = $true
$lblBranch.Location = New-Object System.Drawing.Point(28,382)
$form.Controls.Add($lblBranch)

$txtBranch = New-Object System.Windows.Forms.TextBox
$txtBranch.Location = New-Object System.Drawing.Point(28,406)
$txtBranch.Size = New-Object System.Drawing.Size(500,28)
$form.Controls.Add($txtBranch)

$groupAfter = New-Object System.Windows.Forms.GroupBox
$groupAfter.Text = '머지 후 feature 브랜치'
$groupAfter.Location = New-Object System.Drawing.Point(550,382)
$groupAfter.Size = New-Object System.Drawing.Size(260,78)
$form.Controls.Add($groupAfter)

$radioDelete = New-Object System.Windows.Forms.RadioButton
$radioDelete.Text = '로컬 + 원격 삭제'
$radioDelete.Location = New-Object System.Drawing.Point(14,24)
$radioDelete.AutoSize = $true
$radioDelete.Checked = $true
$groupAfter.Controls.Add($radioDelete)

$radioKeep = New-Object System.Windows.Forms.RadioButton
$radioKeep.Text = '유지'
$radioKeep.Location = New-Object System.Drawing.Point(14,48)
$radioKeep.AutoSize = $true
$groupAfter.Controls.Add($radioKeep)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Develop에 반영'
$btnRun.Font = New-Object System.Drawing.Font('Malgun Gothic',11,[System.Drawing.FontStyle]::Bold)
$btnRun.Location = New-Object System.Drawing.Point(28,455)
$btnRun.Size = New-Object System.Drawing.Size(500,42)
$btnRun.Enabled = $false
$form.Controls.Add($btnRun)

$btnCreateBranch = New-Object System.Windows.Forms.Button
$btnCreateBranch.Text = '현재 커밋에서 브랜치 생성'
$btnCreateBranch.Location = New-Object System.Drawing.Point(28,510)
$btnCreateBranch.Size = New-Object System.Drawing.Size(245,42)
$btnCreateBranch.Enabled = $false
$form.Controls.Add($btnCreateBranch)

$btnMergeDevelop = New-Object System.Windows.Forms.Button
$btnMergeDevelop.Text = '현재 브랜치를 develop에 병합'
$btnMergeDevelop.Location = New-Object System.Drawing.Point(283,510)
$btnMergeDevelop.Size = New-Object System.Drawing.Size(527,42)
$btnMergeDevelop.Enabled = $false
$form.Controls.Add($btnMergeDevelop)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = '업데이트 확인'
$btnUpdate.Location = New-Object System.Drawing.Point(265,20)
$btnUpdate.Size = New-Object System.Drawing.Size(115,28)
$btnUpdate.Font = New-Object System.Drawing.Font('Malgun Gothic',8,[System.Drawing.FontStyle]::Regular)
$form.Controls.Add($btnUpdate)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = '진행 로그'
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(28,575)
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(28,600)
$txtLog.Size = New-Object System.Drawing.Size(782,150)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$form.Controls.Add($txtLog)

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'cqi_client Git 저장소 폴더를 선택하세요.'
    if ($txtRepo.Text -and (Test-Path $txtRepo.Text)) { $dlg.SelectedPath = $txtRepo.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtRepo.Text = $dlg.SelectedPath
        Save-Config $dlg.SelectedPath
        Refresh-View
    }
})

$btnRefresh.Add_Click({ Refresh-View })
$btnRun.Add_Click({ Run-Workflow })
$btnDeleteCommit.Add_Click({ Undo-LastCommit })
$btnCreateBranch.Add_Click({ New-BranchAtHead })
$btnMergeDevelop.Add_Click({ Merge-CurrentBranchToDevelop })
$btnUpdate.Add_Click({ Check-ForUpdate $true })

$savedRepo = Load-Config
if ($savedRepo -and (Test-Path $savedRepo)) {
    $txtRepo.Text = $savedRepo
} else {
    $txtRepo.Text = (Get-Location).Path
}

$form.Add_Shown({
    Refresh-View
    $form.BeginInvoke([Action]{ Check-ForUpdate $false }) | Out-Null
})
[void]$form.ShowDialog()
