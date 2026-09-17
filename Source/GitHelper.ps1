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


$AppName = 'GitHelper v1.0.4'
$AppVersion = [version]'1.0.4'
$GitHubRepo = 'JIINNY-Hee/GitHelper'
$ConfigDir = Join-Path $env:APPDATA 'GitHelper'
$ConfigPath = Join-Path $ConfigDir 'config.json'
$LegacyConfigPath = Join-Path (Join-Path $env:APPDATA 'CQIGitHelper') 'config.json'

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
$script:VisiblePushedCommits = @()
$script:FavoriteRepos = @()
$script:LoadingRepoList = $false
$script:LoadedRepoPath = $null
$script:BaseBranches = @{}
$script:AvailableBaseBranches = @()
$script:LoadingBaseBranch = $false
$script:GitExePath = 'git.exe'

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

    return Invoke-ProcessText -FilePath $script:GitExePath -Arguments $effectiveArgs -WorkingDirectory $script:CurrentRepo
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
    @{
        repoPath = $RepoPath
        favoriteRepos = @($script:FavoriteRepos)
        baseBranches = $script:BaseBranches
    } | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Load-Config {
    $loadPath = if (Test-Path $ConfigPath) { $ConfigPath } elseif (Test-Path $LegacyConfigPath) { $LegacyConfigPath } else { $null }
    if ($loadPath) {
        try {
            $config = Get-Content $loadPath -Raw | ConvertFrom-Json
            $script:FavoriteRepos = @($config.favoriteRepos | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
            $script:BaseBranches = @{}
            if ($config.baseBranches) {
                foreach ($property in $config.baseBranches.PSObject.Properties) { $script:BaseBranches[$property.Name] = [string]$property.Value }
            }
            return $config.repoPath
        } catch { return $null }
    }
    return $null
}

function Sync-FavoriteRepoControl([string]$SelectedPath) {
    $script:LoadingRepoList = $true
    try {
        $txtRepo.Items.Clear()
        foreach ($path in ($script:FavoriteRepos | Sort-Object)) { [void]$txtRepo.Items.Add($path) }
        if ($SelectedPath) { $txtRepo.Text = $SelectedPath }
    } finally { $script:LoadingRepoList = $false }
}

function Sync-BaseBranchControl([string]$RepoPath) {
    $script:LoadingBaseBranch = $true
    try {
        $cmbBaseBranch.Items.Clear()
        foreach ($branch in $script:AvailableBaseBranches) { [void]$cmbBaseBranch.Items.Add($branch) }
        $selected = if ($RepoPath -and $script:BaseBranches.ContainsKey($RepoPath)) { $script:BaseBranches[$RepoPath] } else { 'develop' }
        $cmbBaseBranch.Text = $selected
        $dropDownWidth = $cmbBaseBranch.Width
        foreach ($branch in $script:AvailableBaseBranches) {
            $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$branch, $cmbBaseBranch.Font).Width + 32
            if ($measured -gt $dropDownWidth) { $dropDownWidth = $measured }
        }
        $cmbBaseBranch.DropDownWidth = [Math]::Min(500, $dropDownWidth)
    } finally { $script:LoadingBaseBranch = $false }
}

function Add-CurrentRepoFavorite {
    $path = $txtRepo.Text.Trim()
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { Show-Error '즐겨찾기에 추가할 올바른 저장소 경로를 선택해 주세요.'; return }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if ($script:FavoriteRepos -notcontains $resolved) { $script:FavoriteRepos += $resolved }
    Sync-FavoriteRepoControl $resolved
    Save-Config $resolved
    Append-Log "레포 즐겨찾기 추가: $resolved"
}

function Remove-CurrentRepoFavorite {
    $path = $txtRepo.Text.Trim()
    $script:FavoriteRepos = @($script:FavoriteRepos | Where-Object { $_ -ne $path })
    Sync-FavoriteRepoControl $path
    Save-Config $path
    Append-Log "레포 즐겨찾기 제거: $path"
}

function Test-CommandAvailable([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ';'
}

function Find-GitExecutable {
    $command = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe' })
    ) | Where-Object { $_ }

    return $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Add-GitToUserPath([string]$GitExePath) {
    $gitDir = Split-Path -Parent $GitExePath
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $entries = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $gitDir) {
        $newUserPath = (@($entries) + $gitDir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    }
    Update-ProcessPath
}

function Ensure-Git {
    Update-ProcessPath
    $gitExe = Find-GitExecutable
    if ($gitExe) {
        try { Add-GitToUserPath $gitExe } catch {
            # The absolute path still lets this process use Git even if PATH persistence fails.
        }
        $script:GitExePath = $gitExe
        return $true
    }

    if (-not (Test-CommandAvailable 'winget.exe')) {
        Show-Error "Git이 설치되어 있지 않고 winget도 찾을 수 없어 자동 설치할 수 없습니다.`r`n`r`nhttps://git-scm.com/download/win 에서 Git for Windows를 설치해 주세요."
        return $false
    }

    Append-Log 'Git for Windows를 자동 설치합니다...'
    $install = Invoke-ProcessText -FilePath 'winget.exe' -Arguments @(
        'install','--id','Git.Git','-e','--silent',
        '--accept-package-agreements','--accept-source-agreements'
    )
    if ($install.ExitCode -ne 0) {
        $detail = if ($install.StdErr) { $install.StdErr } else { $install.StdOut }
        Show-Error "Git for Windows 자동 설치에 실패했습니다.`r`n`r`n$detail`r`n`r`nhttps://git-scm.com/download/win 에서 직접 설치해 주세요."
        return $false
    }

    Update-ProcessPath
    $gitExe = Find-GitExecutable
    if (-not $gitExe) {
        Show-Error 'Git 설치는 완료되었지만 git.exe를 찾지 못했습니다. Windows에 다시 로그인한 뒤 실행해 주세요.'
        return $false
    }

    try { Add-GitToUserPath $gitExe } catch {
        Show-Error "Git은 설치되었지만 사용자 PATH 등록에 실패했습니다.`r`n`r`n$($_.Exception.Message)"
        return $false
    }
    $script:GitExePath = $gitExe
    Append-Log "Git 준비 완료: $gitExe"
    return $true
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

function Get-GitHubRepoName {
    $origin = Invoke-Git -GitArgs @('remote','get-url','origin')
    if ($origin.ExitCode -ne 0) { return $null }
    if ($origin.StdOut -match '(?i)github\.com[/:](?<owner>[^/\s:]+)/(?<repo>[^/\s]+?)(?:\.git)?$') {
        return "$($Matches.owner)/$($Matches.repo)"
    }
    return $null
}

function Select-GitHubAccount([string[]]$Accounts, [string]$RepoName, [string]$PreferredAccount) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'GitHub 계정 선택'
    $dialog.Size = New-Object System.Drawing.Size(440,205)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = $form.Font

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "저장소 '$RepoName'에 사용할 GitHub 계정을 선택하세요."
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(18,18)
    $dialog.Controls.Add($label)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $combo.Location = New-Object System.Drawing.Point(20,55)
    $combo.Size = New-Object System.Drawing.Size(382,28)
    foreach ($account in $Accounts) { [void]$combo.Items.Add($account) }
    $preferredIndex = if ($PreferredAccount) { $combo.Items.IndexOf($PreferredAccount) } else { -1 }
    $combo.SelectedIndex = if ($preferredIndex -ge 0) { $preferredIndex } else { 0 }
    $dialog.Controls.Add($combo)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '선택'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(226,108)
    $ok.Size = New-Object System.Drawing.Size(82,32)
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '취소'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(320,108)
    $cancel.Size = New-Object System.Drawing.Size(82,32)
    $dialog.Controls.Add($cancel)
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel

    try {
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            return [string]$combo.SelectedItem
        }
        return $null
    } finally { $dialog.Dispose() }
}

function Start-GitHubLogin {
    $msg = "이 저장소에 사용할 수 있는 GitHub 계정이 없습니다.`r`n`r`n[예]를 누르면 새 계정 로그인 창을 엽니다."
    $answer = [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'YesNo', 'Question')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    $ghCommand = Get-Command 'gh.exe' -ErrorAction SilentlyContinue
    if (-not $ghCommand) { return $false }
    Append-Log 'GitHub 로그인 창을 엽니다...'
    $proc = Start-Process -FilePath $ghCommand.Source -ArgumentList @('auth','login','--hostname','github.com','--git-protocol','https','--web') -Wait -PassThru
    return ($proc.ExitCode -eq 0)
}

function Ensure-GitHubHttpsAuth([switch]$LoginAttempted) {
    if (-not (Ensure-GitHubCli)) { return $false }

    $status = Invoke-Gh -GhArgs @('auth','status','--hostname','github.com','--json','hosts')
    $accounts = @()
    $activeAccount = $null
    if ($status.ExitCode -eq 0 -and $status.StdOut) {
        try {
            $statusJson = $status.StdOut | ConvertFrom-Json
            $hostAccounts = @($statusJson.hosts.'github.com')
            $accounts = @($hostAccounts | ForEach-Object { $_.login } | Where-Object { $_ } | Select-Object -Unique)
            $activeAccount = [string]($hostAccounts | Where-Object { $_.active } | Select-Object -First 1 -ExpandProperty login)
        } catch { $accounts = @() }
    }

    $repoName = Get-GitHubRepoName
    if (-not $repoName) {
        Show-Error 'origin 주소에서 GitHub 저장소 이름을 확인하지 못했습니다. github.com의 HTTPS 또는 SSH 저장소 주소인지 확인해 주세요.'
        return $false
    }
    $validAccounts = @()
    foreach ($account in $accounts) {
        $switch = Invoke-Gh -GhArgs @('auth','switch','--hostname','github.com','--user',$account)
        if ($switch.ExitCode -ne 0) { continue }
        $permission = Invoke-Gh -GhArgs @('api',"repos/$repoName",'--jq','.permissions.push')
        if ($permission.ExitCode -eq 0 -and $permission.StdOut.Trim().ToLowerInvariant() -eq 'true') {
            $validAccounts += $account
        }
    }

    if ($validAccounts.Count -eq 0) {
        if ($activeAccount) { [void](Invoke-Gh -GhArgs @('auth','switch','--hostname','github.com','--user',$activeAccount)) }
        if (-not $LoginAttempted -and (Start-GitHubLogin)) {
            return Ensure-GitHubHttpsAuth -LoginAttempted
        }
        Show-Error "저장소 '$repoName'에 접근 가능한 GitHub 계정을 찾지 못했습니다.`r`n`r`n로그인 계정에 저장소 push 권한이 있는지 확인해 주세요."
        return $false
    }

    $selectedAccount = if ($validAccounts.Count -eq 1) {
        $validAccounts[0]
    } else {
        Select-GitHubAccount -Accounts $validAccounts -RepoName $repoName -PreferredAccount $activeAccount
    }
    if (-not $selectedAccount) { return $false }

    $switch = Invoke-Gh -GhArgs @('auth','switch','--hostname','github.com','--user',$selectedAccount)
    if ($switch.ExitCode -ne 0) {
        Show-Error "GitHub 계정을 '$selectedAccount'(으)로 전환하지 못했습니다.`r`n`r`n$($switch.StdErr)"
        return $false
    }
    Append-Log "GitHub 계정 선택 완료: $selectedAccount ($repoName)"

    $setup = Invoke-Gh -GhArgs @('auth','setup-git','--hostname','github.com')
    if ($setup.ExitCode -ne 0) {
        Show-Error "Git 자격 증명 연결에 실패했습니다.`r`n`r`n$($setup.StdErr)"
        return $false
    }
    return $true
}

function Fetch-Origin {
    $fetch = Invoke-Git -GitArgs @('fetch','origin','--prune')
    if ($fetch.ExitCode -eq 0) { return $true }
    throw "origin fetch 실패:`r`n$($fetch.StdErr)`r`n`r`n저장소의 origin 주소는 변경하지 않았습니다. Git/Fork 인증 설정을 확인해 주세요."
}

function Remove-RemoteBranch([string]$BranchName) {
    if (-not $BranchName) { throw '삭제할 원격 브랜치 이름이 비어 있습니다.' }
    Append-Log "원격 브랜치 삭제 요청: origin/$BranchName"
    $delete = Invoke-Git -GitArgs @('push','origin','--delete',$BranchName)
    $verify = Invoke-Git -GitArgs @('ls-remote','--exit-code','--heads','origin',$BranchName)
    if ($verify.ExitCode -eq 0 -and $verify.StdOut) {
        $detail = if ($delete.StdErr) { $delete.StdErr } else { '원격 저장소가 삭제 요청 후에도 브랜치를 반환했습니다.' }
        throw "원격 브랜치 'origin/$BranchName' 삭제에 실패했습니다.`r`n`r`n$detail"
    }
    if ($verify.ExitCode -ne 2) {
        throw "원격 브랜치 삭제 여부를 확인하지 못했습니다.`r`n`r`n$($verify.StdErr)"
    }
    [void](Invoke-Git -GitArgs @('fetch','origin','--prune'))
    Append-Log "원격 feature 브랜치 삭제 확인 완료: origin/$BranchName"
}

function Get-RepoState([string]$Repo, [switch]$Fast) {
    if (-not $Repo -or -not (Test-Path -LiteralPath $Repo)) { throw '선택한 저장소 폴더가 존재하지 않습니다.' }
    $script:CurrentRepo = (Resolve-Path -LiteralPath $Repo).Path
    $inside = Invoke-Git -GitArgs @('rev-parse','--is-inside-work-tree')
    if ($inside.ExitCode -ne 0 -or $inside.StdOut -ne 'true') { throw '선택한 폴더가 Git 저장소가 아닙니다.' }

    $root = Invoke-Git -GitArgs @('rev-parse','--show-toplevel')
    if ($root.ExitCode -ne 0) { throw 'Git 저장소 루트를 확인하지 못했습니다.' }
    $Repo = $root.StdOut
    $script:CurrentRepo = $Repo

    $originResult = Invoke-Git -GitArgs @('remote','get-url','origin')
    if ($originResult.ExitCode -ne 0) { throw 'origin remote를 찾을 수 없습니다.' }
    $origin = $originResult.StdOut
    if (-not $Fast) {
        [void](Fetch-Origin)
    }

    $branchRefs = Invoke-Git -GitArgs @('for-each-ref','--format=%(refname:short)','refs/remotes/origin')
    $script:AvailableBaseBranches = if ($branchRefs.ExitCode -eq 0 -and $branchRefs.StdOut) {
        @($branchRefs.StdOut -split "`r?`n" | Where-Object { $_ -match '^origin/.+' -and $_ -ne 'origin/HEAD' } | ForEach-Object { $_.Substring(7) } | Sort-Object -Unique)
    } else { @() }
    $baseBranch = if ($script:BaseBranches.ContainsKey($Repo)) { $script:BaseBranches[$Repo] } else { 'develop' }
    $baseRef = "origin/$baseBranch"
    $base = Invoke-Git -GitArgs @('rev-parse','--verify',$baseRef)
    if ($base.ExitCode -ne 0) { throw "설정한 기본 브랜치 '$baseBranch'를 origin에서 찾을 수 없습니다. 기본 브랜치를 변경해 주세요." }

    $branch = Invoke-Git -GitArgs @('branch','--show-current')
    $head = Invoke-Git -GitArgs @('rev-parse','HEAD')
    $statusArgs = if ($Fast) { @('status','--porcelain=v1','--untracked-files=no') } else { @('status','--porcelain=v1') }
    $status = Invoke-Git -GitArgs $statusArgs
    $log = Invoke-Git -GitArgs @('log','--reverse','--encoding=UTF-8','--format=%H%x09%h%x09%s',"$baseRef..HEAD")

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
        BaseRef = $baseRef
        BaseBranch = $baseBranch
        Branch = $branch.StdOut
        Head = $head.StdOut
        Dirty = [bool]$status.StdOut
        StatusText = $status.StdOut
        Commits = $commits
    }
}

function Get-MyPushedCommits {
    $emailResult = Invoke-Git -GitArgs @('config','user.email')
    if ($emailResult.ExitCode -ne 0 -or -not $emailResult.StdOut.Trim()) { return @() }
    $log = Invoke-Git -GitArgs @('log','--remotes=origin',"--author=$($emailResult.StdOut.Trim())",'--date=format-local:%Y-%m-%d %H:%M','--format=%H%x09%h%x09%ad%x09%s','-n','200')
    $commits = @()
    if ($log.ExitCode -eq 0 -and $log.StdOut) {
        foreach ($line in ($log.StdOut -split "`r?`n")) {
            $parts = $line -split "`t",4
            if ($parts.Count -eq 4) { $commits += [pscustomobject]@{ Full=$parts[0]; Short=$parts[1]; Date=$parts[2]; Subject=$parts[3] } }
        }
    }
    return $commits
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
    $btnAddFavorite.Enabled = -not $Busy
    $btnRemoveFavorite.Enabled = -not $Busy
    $btnRun.Enabled = -not $Busy
    $btnDeleteCommit.Enabled = (-not $Busy) -and ($script:VisibleCommits.Count -gt 0)
    $btnChangedFiles.Enabled = (-not $Busy) -and (($script:VisibleCommits.Count -gt 0) -or ($script:VisiblePushedCommits.Count -gt 0))
    $btnCreateBranch.Enabled = -not $Busy
    $btnMergeDevelop.Enabled = (-not $Busy) -and ($btnMergeDevelop.Tag -eq 'Allowed')
    $btnUpdate.Enabled = -not $Busy
    $cmbBaseBranch.Enabled = -not $Busy
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
    $stashWasUsed = $false
    try {
        $state = Get-RepoState $repo
        $sourceBranch = $state.Branch
        $baseBranch = $state.BaseBranch
        if (-not $sourceBranch) { throw '분리된 HEAD 상태에서는 병합할 수 없습니다.' }
        if ($sourceBranch -eq 'main') { throw 'main 브랜치는 직접 push하거나 작업 브랜치로 병합할 수 없습니다.' }
        if ($sourceBranch -eq $baseBranch) { throw "현재 브랜치가 이미 기본 브랜치 '$baseBranch'입니다." }

        $dirtyNotice = if ($state.Dirty) { "`r`n`r`n미커밋 파일은 자동으로 임시 보관한 뒤 원래 브랜치에 복원합니다." } else { '' }
        $answer = [System.Windows.Forms.MessageBox]::Show("현재 브랜치로 $baseBranch 대상 PR을 만들고 병합합니다.`r`n`r`n$sourceBranch  →  $baseBranch$dirtyNotice`r`n`r`n계속할까요?", $AppName, 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        if ($state.Dirty) {
            Append-Log '미커밋 파일을 안전하게 임시 보관합니다...'
            $stash = Invoke-Git -GitArgs @('stash','push','-u','-m',"GitHelper merge $(Get-Date -Format s)")
            if ($stash.ExitCode -ne 0) { throw "stash 실패:`r`n$($stash.StdErr)" }
            $stashRef = Invoke-Git -GitArgs @('rev-parse','stash@{0}')
            if ($stashRef.ExitCode -ne 0) { throw '생성한 stash를 확인하지 못했습니다.' }
            $stashHash = $stashRef.StdOut
            $stashWasUsed = $true
            Append-Log "미커밋 파일 보관 완료: $($stashHash.Substring(0,8))"
        }

        if (-not (Ensure-GitHubHttpsAuth)) { throw 'GitHub 인증을 완료하지 못했습니다.' }

        Append-Log "현재 브랜치를 origin에 push합니다: $sourceBranch"
        $push = Invoke-Git -GitArgs @('push','-u','origin',$sourceBranch)
        if ($push.ExitCode -ne 0) { throw "현재 브랜치 push 실패:`r`n$($push.StdErr)" }

        $title = if ($state.Commits.Count -gt 0) { $state.Commits[-1].Subject } else { "Merge $sourceBranch into develop" }
        $body = "GitHelper에서 현재 브랜치 '$sourceBranch'를 $baseBranch에 병합하기 위해 생성한 PR입니다."

        Append-Log "$baseBranch 대상 PR을 생성합니다..."
        $pr = Invoke-Gh -GhArgs @('pr','create','--base',$baseBranch,'--head',$sourceBranch,'--title',$title,'--body',$body)
        if ($pr.ExitCode -eq 0) {
            $prUrl = ($pr.StdOut -split "`r?`n" | Select-Object -Last 1).Trim()
        } else {
            $existing = Invoke-Gh -GhArgs @('pr','view',$sourceBranch,'--json','url','--jq','.url')
            if ($existing.ExitCode -ne 0) { throw "PR 생성 실패:`r`n$($pr.StdErr)" }
            $prUrl = $existing.StdOut.Trim()
            Append-Log "기존 PR을 사용합니다: $prUrl"
        }

        Append-Log 'PR을 rebase merge 합니다...'
        $merge = Invoke-Gh -GhArgs @('pr','merge',$sourceBranch,'--rebase')
        if ($merge.ExitCode -ne 0) { throw "PR 병합이 완료되지 않았습니다.`r`n리뷰나 CI 조건을 확인해 주세요.`r`n`r`nPR: $prUrl`r`n`r`n$($merge.StdErr)" }

        Append-Log "병합된 origin/$baseBranch을 동기화합니다..."
        $fetch = Invoke-Git -GitArgs @('fetch','origin','--prune')
        if ($fetch.ExitCode -ne 0) { throw "병합 후 fetch 실패:`r`n$($fetch.StdErr)" }
        $checkout = Invoke-Git -GitArgs @('switch',$baseBranch)
        if ($checkout.ExitCode -ne 0) { throw "$baseBranch 이동 실패:`r`n$($checkout.StdErr)" }
        $sync = Invoke-Git -GitArgs @('reset','--hard',$state.BaseRef)
        if ($sync.ExitCode -ne 0) { throw "로컬 $baseBranch 동기화 실패:`r`n$($sync.StdErr)" }

        $back = Invoke-Git -GitArgs @('switch',$sourceBranch)
        if ($back.ExitCode -ne 0) { throw "원래 브랜치 '$sourceBranch' 복귀 실패:`r`n$($back.StdErr)" }
        if ($stashHash) {
            Restore-Stash $stashHash
            $stashHash = $null
        }

        if ($radioDelete.Checked -and (-not $stashWasUsed -or $script:LastStashRestoreSucceeded)) {
            Append-Log '병합한 feature 브랜치를 정리합니다...'
            $currentAfterMerge = Invoke-Git -GitArgs @('branch','--show-current')
            if ($currentAfterMerge.ExitCode -eq 0 -and $currentAfterMerge.StdOut -eq $sourceBranch) {
                [void](Invoke-Git -GitArgs @('switch',$baseBranch))
            }
            $delLocal = Invoke-Git -GitArgs @('branch','-D',$sourceBranch)
            if ($delLocal.ExitCode -eq 0) { Append-Log '로컬 feature 브랜치 삭제 완료.' }
            else { Append-Log '로컬 feature 브랜치 삭제 실패 또는 이미 없음.' }
            Remove-RemoteBranch $sourceBranch
        } else {
            Append-Log 'feature 브랜치를 유지합니다.'
        }
        Append-Log "현재 브랜치를 $baseBranch에 병합했습니다."
        Show-Info "$sourceBranch 브랜치를 PR을 통해 $baseBranch에 병합했습니다.`r`n`r`n$prUrl"
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

function Show-UpdateDialog([version]$LatestVersion, [string]$ChangeLog) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'GitHelper 업데이트'
    $dialog.Size = New-Object System.Drawing.Size(720,600)
    $dialog.MinimumSize = New-Object System.Drawing.Size(560,420)
    $dialog.MaximumSize = New-Object System.Drawing.Size(900,720)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowIcon = $false
    $dialog.Font = $form.Font

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    $layout.Padding = New-Object System.Windows.Forms.Padding(16,10,16,10)
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,48)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,54)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Label
    $header.Text = "새 버전 v$LatestVersion이 있습니다. (현재 v$AppVersion)"
    $header.Dock = [System.Windows.Forms.DockStyle]::Fill
    $header.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $header.Font = New-Object System.Drawing.Font($dialog.Font, [System.Drawing.FontStyle]::Bold)
    $layout.Controls.Add($header,0,0)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.Padding = New-Object System.Windows.Forms.Padding(0,10,0,0)

    $laterButton = New-Object System.Windows.Forms.Button
    $laterButton.Text = '나중에'
    $laterButton.DialogResult = [System.Windows.Forms.DialogResult]::No
    $laterButton.Size = New-Object System.Drawing.Size(96,34)
    $buttonPanel.Controls.Add($laterButton)

    $updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Text = '업데이트'
    $updateButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $updateButton.Size = New-Object System.Drawing.Size(96,34)
    $buttonPanel.Controls.Add($updateButton)
    $layout.Controls.Add($buttonPanel,0,2)

    $changeLogBox = New-Object System.Windows.Forms.RichTextBox
    $changeLogBox.ReadOnly = $true
    $changeLogBox.WordWrap = $true
    $changeLogBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $changeLogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $changeLogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $changeLogBox.BackColor = [System.Drawing.SystemColors]::Window
    $changeLogBox.Text = "[ChangeLog]`r`n`r`n$ChangeLog"
    $changeLogBox.Margin = New-Object System.Windows.Forms.Padding(0)
    $layout.Controls.Add($changeLogBox,0,1)

    $dialog.AcceptButton = $updateButton
    $dialog.CancelButton = $laterButton
    try {
        $dialog.ActiveControl = $updateButton
        return $dialog.ShowDialog($form)
    } finally { $dialog.Dispose() }
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
        $answer = Show-UpdateDialog -LatestVersion $latest -ChangeLog $changeLog
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

function Show-ChangedFilesWindow {
    param([string[]]$Paths)
    $repo = $txtRepo.Text.Trim()
    if (-not $repo -or -not (Test-Path -LiteralPath $repo)) { Show-Error '올바른 저장소 폴더를 먼저 선택해 주세요.'; return }
    try {
        if (-not $PSBoundParameters.ContainsKey('Paths')) {
            $state = Get-RepoState $repo -Fast
            $diff = Invoke-Git -GitArgs @('diff','--name-only',"$($state.BaseRef)..HEAD")
            if ($diff.ExitCode -ne 0) { throw "변경 파일 확인 실패:`r`n$($diff.StdErr)" }
            $Paths = if ($diff.StdOut) { @($diff.StdOut -split "`r?`n") } else { @() }
        }
        $groups = [ordered]@{ Prefab=@(); CSharp=@(); Image=@(); Material=@(); Shader=@() }
        if ($Paths) {
            foreach ($path in $Paths) {
                $path = $path.Trim(); if (-not $path) { continue }
                $lower = $path.ToLowerInvariant()
                if ($lower -match '\.prefab$') { $groups.Prefab += $path }
                elseif ($lower -match '\.cs$') { $groups.CSharp += $path }
                elseif ($lower -match '\.(png|jpg|jpeg|tga|psd|tif|tiff|gif|bmp|exr|webp|svg)$') { $groups.Image += $path }
                elseif ($lower -match '\.mat$') { $groups.Material += $path }
                elseif ($lower -match '\.(shader|shadergraph|shadersubgraph|vfx|compute)$') { $groups.Shader += $path }
            }
        }
        $fileForm = New-Object System.Windows.Forms.Form
        $fileForm.Text = 'GitHelper - Push 변경 파일'; $fileForm.Size = New-Object System.Drawing.Size(720,620)
        $fileForm.MinimumSize = New-Object System.Drawing.Size(520,400)
        $fileForm.StartPosition = 'CenterParent'; $fileForm.Font = New-Object System.Drawing.Font('Malgun Gothic',9)
        $fileForm.BackColor = [System.Drawing.SystemColors]::Control; $fileForm.ForeColor = [System.Drawing.SystemColors]::ControlText
        try { $fileForm.Icon = $form.Icon } catch {}

        $definitions = @(
            @{Title='Prefab';Key='Prefab'}, @{Title='C#';Key='CSharp'},
            @{Title='이미지';Key='Image'}, @{Title='Material';Key='Material'},
            @{Title='Shader';Key='Shader'}
        )
        $collapsedGroups = @{}
        $rowKinds = New-Object System.Collections.ArrayList

        $btnExpandAll = New-Object System.Windows.Forms.Button
        $btnExpandAll.Text = '전체 펼치기'; $btnExpandAll.Location = New-Object System.Drawing.Point(16,14); $btnExpandAll.Size = New-Object System.Drawing.Size(110,30)
        $fileForm.Controls.Add($btnExpandAll)

        $btnCollapseAll = New-Object System.Windows.Forms.Button
        $btnCollapseAll.Text = '전체 접기'; $btnCollapseAll.Location = New-Object System.Drawing.Point(134,14); $btnCollapseAll.Size = New-Object System.Drawing.Size(110,30)
        $fileForm.Controls.Add($btnCollapseAll)

        $changedFilesList = New-Object System.Windows.Forms.ListBox
        $changedFilesList.Location = New-Object System.Drawing.Point(16,52); $changedFilesList.Size = New-Object System.Drawing.Size(670,485)
        $changedFilesList.Anchor = 'Top,Bottom,Left,Right'; $changedFilesList.BorderStyle = 'FixedSingle'
        $changedFilesList.BackColor = [System.Drawing.SystemColors]::Window; $changedFilesList.ForeColor = [System.Drawing.SystemColors]::WindowText
        $changedFilesList.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
        $fileForm.Controls.Add($changedFilesList)

        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = '분류 제목을 더블 클릭해 접거나 펼칠 수 있습니다.  Ctrl+A: 전체 선택  /  Ctrl+C: 복사'
        $hint.AutoSize = $true; $hint.Location = New-Object System.Drawing.Point(16,548); $hint.Anchor = 'Bottom,Left'
        $fileForm.Controls.Add($hint)

        $btnCopyFiles = New-Object System.Windows.Forms.Button
        $btnCopyFiles.Text = '선택 항목 복사'; $btnCopyFiles.Size = New-Object System.Drawing.Size(140,30)
        $btnCopyFiles.Location = New-Object System.Drawing.Point(546,14); $btnCopyFiles.Anchor = 'Top,Right'
        $fileForm.Controls.Add($btnCopyFiles)

        $refreshChangedFilesList = {
            $changedFilesList.BeginUpdate()
            try {
                $changedFilesList.Items.Clear(); $rowKinds.Clear()
                foreach ($definition in $definitions) {
                    $key = $definition.Key
                    if ($groups[$key].Count -eq 0) { continue }
                    $isCollapsed = [bool]$collapsedGroups[$key]
                    $marker = if ($isCollapsed) { [char]0x25B6 } else { [char]0x25BC }
                    [void]$changedFilesList.Items.Add("$marker  $($definition.Title) ($($groups[$key].Count))")
                    [void]$rowKinds.Add("group:$key")
                    if (-not $isCollapsed) {
                        foreach ($item in @($groups[$key] | Sort-Object)) {
                            [void]$changedFilesList.Items.Add("    $([System.IO.Path]::GetFileNameWithoutExtension($item))")
                            [void]$rowKinds.Add('file')
                        }
                    }
                }
            } finally { $changedFilesList.EndUpdate() }
        }

        $copySelectedFiles = {
            $lines = New-Object System.Collections.Generic.List[string]
            foreach ($index in $changedFilesList.SelectedIndices) {
                if ($rowKinds[[int]$index] -eq 'file') { $lines.Add($changedFilesList.Items[[int]$index].ToString().Trim()) }
            }
            if ($lines.Count -gt 0) { [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n")) }
        }

        $changedFilesList.Add_DoubleClick({
            $index = $changedFilesList.IndexFromPoint($changedFilesList.PointToClient([System.Windows.Forms.Cursor]::Position))
            if ($index -ge 0 -and $rowKinds[$index] -like 'group:*') {
                $key = $rowKinds[$index].Substring(6); $collapsedGroups[$key] = -not [bool]$collapsedGroups[$key]
                & $refreshChangedFilesList
            }
        })
        $changedFilesList.Add_KeyDown({
            param($sender,$eventArgs)
            if ($eventArgs.Control -and $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::A) {
                for ($index = 0; $index -lt $changedFilesList.Items.Count; $index++) {
                    $changedFilesList.SetSelected($index, $rowKinds[$index] -eq 'file')
                }
                $eventArgs.SuppressKeyPress = $true
            } elseif ($eventArgs.Control -and $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::C) {
                & $copySelectedFiles; $eventArgs.SuppressKeyPress = $true
            }
        })
        $btnCopyFiles.Add_Click({ & $copySelectedFiles })
        $btnExpandAll.Add_Click({ foreach ($definition in $definitions) { $collapsedGroups[$definition.Key] = $false }; & $refreshChangedFilesList })
        $btnCollapseAll.Add_Click({ foreach ($definition in $definitions) { $collapsedGroups[$definition.Key] = $true }; & $refreshChangedFilesList })
        & $refreshChangedFilesList
        [void]$fileForm.ShowDialog($form); $fileForm.Dispose()
    } catch { Show-Error $_.Exception.Message }
}

function Show-SelectedChangedFiles {
    if ($listPushedCommits.SelectedIndices.Count -gt 0) {
        $files = New-Object System.Collections.Generic.List[string]
        foreach ($index in $listPushedCommits.SelectedIndices) {
            if ([int]$index -ge $script:VisiblePushedCommits.Count) { continue }
            $result = Invoke-Git -GitArgs @('diff-tree','--root','--no-commit-id','--name-only','-r',$script:VisiblePushedCommits[[int]$index].Full)
            if ($result.ExitCode -eq 0 -and $result.StdOut) {
                foreach ($path in ($result.StdOut -split "`r?`n")) {
                    $path = $path.Trim()
                    if ($path -and -not $files.Contains($path)) { $files.Add($path) }
                }
            }
        }
        Show-ChangedFilesWindow -Paths @($files)
        return
    }
    Show-ChangedFilesWindow
}

function Show-LastPushWindow {
    $repo = $txtRepo.Text.Trim()
    if (-not $repo -or -not (Test-Path -LiteralPath $repo)) { Show-Error '올바른 저장소 폴더를 먼저 선택해 주세요.'; return }
    try {
        [void](Get-RepoState $repo)
        $emailResult = Invoke-Git -GitArgs @('config','user.email')
        if ($emailResult.ExitCode -ne 0 -or -not $emailResult.StdOut.Trim()) { throw 'Git user.email이 설정되어 있지 않아 내 Push 커밋을 구분할 수 없습니다.' }
        $userEmail = $emailResult.StdOut.Trim()
        $log = Invoke-Git -GitArgs @('log','--remotes=origin','--all-match',"--author=$userEmail",'--date=format-local:%Y-%m-%d %H:%M','--format=%H%x09%h%x09%ad%x09%s','-n','200')
        if ($log.ExitCode -ne 0) { throw "원격 Push 목록을 읽지 못했습니다:`r`n$($log.StdErr)" }
        $pushedCommits = @()
        if ($log.StdOut) {
            foreach ($line in ($log.StdOut -split "`r?`n")) {
                $parts = $line -split "`t",4
                if ($parts.Count -eq 4) { $pushedCommits += [pscustomobject]@{ Full=$parts[0]; Short=$parts[1]; Date=$parts[2]; Subject=$parts[3] } }
            }
        }

    $historyForm = New-Object System.Windows.Forms.Form
    $historyForm.Text = 'GitHelper - 내 Push 목록'; $historyForm.Size = New-Object System.Drawing.Size(820,520)
    $historyForm.MinimumSize = New-Object System.Drawing.Size(520,340); $historyForm.StartPosition = 'CenterParent'
    $historyForm.Font = New-Object System.Drawing.Font('Malgun Gothic',9)
    try { $historyForm.Icon = $form.Icon } catch {}

    $summary = New-Object System.Windows.Forms.Label
    $summary.Text = "origin에 반영된 내 커밋 ($userEmail)"
    $summary.Location = New-Object System.Drawing.Point(16,16); $summary.AutoSize = $true
    $historyForm.Controls.Add($summary)

    $commitList = New-Object System.Windows.Forms.ListBox
    $commitList.Location = New-Object System.Drawing.Point(16,46); $commitList.Size = New-Object System.Drawing.Size(770,370)
    $commitList.Anchor = 'Top,Bottom,Left,Right'; $commitList.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
    foreach ($commit in $pushedCommits) { [void]$commitList.Items.Add("$($commit.Date)   $($commit.Short)   $($commit.Subject)") }
    if ($commitList.Items.Count -eq 0) { [void]$commitList.Items.Add('(origin에서 내 커밋을 찾지 못했습니다)') }
    $historyForm.Controls.Add($commitList)

    $btnHistoryFiles = New-Object System.Windows.Forms.Button
    $btnHistoryFiles.Text = '선택 커밋의 변경 파일'; $btnHistoryFiles.Size = New-Object System.Drawing.Size(210,32)
    $btnHistoryFiles.Location = New-Object System.Drawing.Point(576,427); $btnHistoryFiles.Anchor = 'Bottom,Right'
    $btnHistoryFiles.Enabled = ($pushedCommits.Count -gt 0)
    $btnHistoryFiles.Add_Click({
        $files = New-Object System.Collections.Generic.List[string]
        foreach ($index in $commitList.SelectedIndices) {
            if ([int]$index -ge $pushedCommits.Count) { continue }
            $fileResult = Invoke-Git -GitArgs @('diff-tree','--root','--no-commit-id','--name-only','-r',$pushedCommits[[int]$index].Full)
            if ($fileResult.ExitCode -eq 0 -and $fileResult.StdOut) {
                foreach ($path in ($fileResult.StdOut -split "`r?`n")) { if ($path.Trim() -and -not $files.Contains($path.Trim())) { $files.Add($path.Trim()) } }
            }
        }
        if ($commitList.SelectedIndices.Count -eq 0) { Show-Info '변경 파일을 볼 커밋을 먼저 선택해 주세요.' }
        else { Show-ChangedFilesWindow -Paths @($files) }
    })
    $historyForm.Controls.Add($btnHistoryFiles)

    [void]$historyForm.ShowDialog($form); $historyForm.Dispose()
    } catch { Show-Error $_.Exception.Message }
}

function Restore-Stash([string]$StashHash) {
    if (-not $StashHash) { return }
    $script:LastStashRestoreSucceeded = $false
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
        else { Append-Log '미커밋 작업 파일 복원 완료.'; $script:LastStashRestoreSucceeded = $true }
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

        if ($state.Commits.Count -eq 0) { throw "$($state.BaseRef) 이후 처리할 커밋이 없습니다." }

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

        Append-Log "$($state.BaseRef) 기준 feature 생성: $feature"
        $checkout = Invoke-Git -GitArgs @('checkout','-b',$feature,$state.BaseRef)
        if ($checkout.ExitCode -ne 0) { throw "feature 브랜치 생성 실패:`r`n$($checkout.StdErr)" }

        foreach ($commit in $state.Commits) {
            Append-Log "커밋 적용: $($commit.Short) $($commit.Subject)"
            $cp = Invoke-Git -GitArgs @('cherry-pick',$commit.Full)
            if ($cp.ExitCode -ne 0) {
                [void](Invoke-Git -GitArgs @('cherry-pick','--abort'))
                throw "cherry-pick 충돌이 발생했습니다.`r`n커밋: $($commit.Short) $($commit.Subject)`r`n`r`n자동 처리를 중단했습니다."
            }
        }

        if (-not (Ensure-GitHubHttpsAuth)) { throw 'GitHub 인증을 완료하지 못했습니다.' }

        Append-Log 'feature 브랜치를 origin에 push 합니다...'
        $push = Invoke-Git -GitArgs @('push','-u','origin',$feature)
        if ($push.ExitCode -ne 0) {
            $pushErr = $push.StdErr
            $authRelated = ($pushErr -match 'Permission denied \(publickey\)') -or ($pushErr -match 'Authentication failed') -or ($pushErr -match 'Could not read from remote repository') -or ($pushErr -match 'could not read Username')
            if ($authRelated) {
                throw "feature push 인증 실패:`r`n$pushErr`r`n`r`n저장소의 origin 주소는 변경하지 않았습니다. Git/Fork 인증 설정을 확인해 주세요."
            }
            if ($push.ExitCode -ne 0) { throw "feature push 실패:`r`n$($push.StdErr)" }
        }
        $featurePushed = $true

        $title = $state.Commits[-1].Subject
        if ($state.Commits.Count -gt 1) { $title = "$title 외 $($state.Commits.Count - 1)건" }
        $body = "GitHelper에서 Fork 커밋 $($state.Commits.Count)개를 추적해 생성한 PR입니다."

        Append-Log "$($state.BaseBranch) 대상 PR을 생성합니다..."
        $pr = Invoke-Gh -GhArgs @('pr','create','--base',$state.BaseBranch,'--head',$feature,'--title',$title,'--body',$body)
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

        if ($originalBranch -eq $state.BaseBranch) {
            $coDev = Invoke-Git -GitArgs @('checkout',$state.BaseBranch)
            if ($coDev.ExitCode -ne 0) { throw "$($state.BaseBranch) checkout 실패:`r`n$($coDev.StdErr)" }
            $reset = Invoke-Git -GitArgs @('reset','--hard',$state.BaseRef)
            if ($reset.ExitCode -ne 0) { throw "$($state.BaseBranch) 동기화 실패:`r`n$($reset.StdErr)" }
        } else {
            $back = Invoke-Git -GitArgs @('checkout',$originalBranch)
            if ($back.ExitCode -ne 0) { throw "원래 브랜치 '$originalBranch' 복귀 실패:`r`n$($back.StdErr)" }
        }

        Restore-Stash $stashHash
        $stashHash = $null

        if ($radioDelete.Checked) {
            Append-Log 'feature 브랜치를 정리합니다...'
            if ((Invoke-Git -GitArgs @('branch','--show-current')).StdOut -eq $feature) {
                [void](Invoke-Git -GitArgs @('checkout',$state.BaseBranch))
            }
            $delLocal = Invoke-Git -GitArgs @('branch','-D',$feature)
            if ($delLocal.ExitCode -eq 0) { Append-Log '로컬 feature 삭제 완료.' }
            else { Append-Log '로컬 feature 삭제 실패 또는 이미 없음.' }

            Remove-RemoteBranch $feature
        } elseif (-not $radioDelete.Checked) {
            Append-Log 'feature 브랜치를 유지합니다.'
        } else {
            Append-Log 'stash 복원 충돌 가능성으로 feature 브랜치를 유지합니다.'
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
    $listPushedCommits.Items.Clear()
    $script:VisiblePushedCommits = @()
    if (-not $repo -or -not (Test-Path $repo)) {
        $script:AvailableBaseBranches = @()
        Sync-BaseBranchControl $null
        $lblPushedCommits.Text = '내 Push 목록 (저장소를 선택해 주세요)'
        $lblStatus.Text = '저장소를 선택해 주세요.'
        $listCommits.Items.Clear()
        $listPushedCommits.Items.Clear()
        $script:VisibleCommits = @()
        $script:VisiblePushedCommits = @()
        $btnDeleteCommit.Enabled = $false
        $btnChangedFiles.Enabled = $false
        $btnRun.Enabled = $false
        $btnCreateBranch.Enabled = $false
        $btnMergeDevelop.Enabled = $false
        $btnMergeDevelop.Tag = 'Blocked'
        return
    }

    $script:LoadedRepoPath = (Resolve-Path -LiteralPath $repo).Path

    try {
        $state = Get-RepoState $repo -Fast
        $script:LoadedRepoPath = $state.Repo
        Sync-BaseBranchControl $state.Repo
        $btnMergeDevelop.Text = "현재 브랜치를 $($state.BaseBranch)에 병합"
        $lblPushedCommits.Text = "내 Push 목록 - $(Split-Path -Leaf $state.Repo)"
        $txtRepo.Text = $state.Repo
        Save-Config $state.Repo
        $dirtyText = if ($state.Dirty) { '추적 파일 변경 있음 (작업 시 자동 보호)' } else { '추적 파일 변경 없음 (작업 시 전체 확인)' }
        $lblStatus.Text = "브랜치: $($state.Branch)    |    기준: $($state.BaseBranch)    |    $dirtyText"
        $listCommits.Items.Clear()
        $script:VisibleCommits = @($state.Commits)
        foreach ($c in $state.Commits) {
            [void]$listCommits.Items.Add("$($c.Short)   $($c.Subject)")
        }
        $script:VisiblePushedCommits = @(Get-MyPushedCommits)
        foreach ($c in $script:VisiblePushedCommits) {
            [void]$listPushedCommits.Items.Add("$($c.Date)   $($c.Short)   $($c.Subject)")
        }
        if ($state.Commits.Count -gt 0) {
            $txtBranch.Text = Make-BranchSuggestion $state.Commits
            $btnRun.Enabled = $true
            $btnDeleteCommit.Enabled = $true
            $btnChangedFiles.Enabled = $true
            $lblCommitCount.Text = "처리할 커밋: $($state.Commits.Count)개"
        } else {
            $btnRun.Enabled = $false
            $btnDeleteCommit.Enabled = $false
            $btnChangedFiles.Enabled = $false
            $lblCommitCount.Text = '처리할 커밋: 0개'
        }
        $btnCreateBranch.Enabled = $true
        $btnMergeDevelop.Enabled = ($state.Branch -and $state.Branch -ne $state.BaseBranch -and $state.Branch -ne 'main')
        $btnMergeDevelop.Tag = if ($btnMergeDevelop.Enabled) { 'Allowed' } else { 'Blocked' }
        $btnChangedFiles.Enabled = (($script:VisibleCommits.Count -gt 0) -or ($script:VisiblePushedCommits.Count -gt 0))
    }
    catch {
        $lblPushedCommits.Text = '내 Push 목록 (조회 실패)'
        Sync-BaseBranchControl $script:LoadedRepoPath
        $lblStatus.Text = "확인 실패: $($_.Exception.Message)"
        $listCommits.Items.Clear()
        $listPushedCommits.Items.Clear()
        $script:VisibleCommits = @()
        $script:VisiblePushedCommits = @()
        $btnDeleteCommit.Enabled = $false
        $btnChangedFiles.Enabled = $false
        $btnRun.Enabled = $false
        $btnCreateBranch.Enabled = $false
        $btnMergeDevelop.Enabled = $false
        $btnMergeDevelop.Tag = 'Blocked'
    }
}

# ---------------- UI ----------------
function Set-ModernButtonStyle($Button, [bool]$Primary = $false) {
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $Button.UseVisualStyleBackColor = $true
    $Button.Cursor = [System.Windows.Forms.Cursors]::Default
    $Button.ForeColor = [System.Drawing.SystemColors]::ControlText
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $AppName
$form.Size = New-Object System.Drawing.Size(860,987)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(860,987)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font('Malgun Gothic',10,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point)
$form.BackColor = [System.Drawing.SystemColors]::Control
$form.ForeColor = [System.Drawing.SystemColors]::ControlText
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {}

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'GitHelper v1.0.4'
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

$txtRepo = New-Object System.Windows.Forms.ComboBox
$txtRepo.Location = New-Object System.Drawing.Point(28,120)
$txtRepo.Size = New-Object System.Drawing.Size(420,28)
$txtRepo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$txtRepo.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend
$txtRepo.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::ListItems
$txtRepo.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
$txtRepo.BackColor = [System.Drawing.SystemColors]::Window
$txtRepo.ForeColor = [System.Drawing.SystemColors]::WindowText
$form.Controls.Add($txtRepo)

$btnAddFavorite = New-Object System.Windows.Forms.Button
$btnAddFavorite.Text = '+ 즐겨찾기'
$btnAddFavorite.Location = New-Object System.Drawing.Point(458,118)
$btnAddFavorite.Size = New-Object System.Drawing.Size(105,32)
$form.Controls.Add($btnAddFavorite)

$btnRemoveFavorite = New-Object System.Windows.Forms.Button
$btnRemoveFavorite.Text = '− 제거'
$btnRemoveFavorite.Location = New-Object System.Drawing.Point(573,118)
$btnRemoveFavorite.Size = New-Object System.Drawing.Size(105,32)
$form.Controls.Add($btnRemoveFavorite)

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
$listCommits.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$listCommits.BackColor = [System.Drawing.SystemColors]::Window
$listCommits.ForeColor = [System.Drawing.SystemColors]::WindowText
$form.Controls.Add($listCommits)

$lblPushedCommits = New-Object System.Windows.Forms.Label
$lblPushedCommits.Text = '내 Push 목록 (origin 반영 커밋)'
$lblPushedCommits.AutoSize = $true
$lblPushedCommits.Font = New-Object System.Drawing.Font('Malgun Gothic',10,[System.Drawing.FontStyle]::Bold)
$lblPushedCommits.Location = New-Object System.Drawing.Point(28,382)
$form.Controls.Add($lblPushedCommits)

$listPushedCommits = New-Object System.Windows.Forms.ListBox
$listPushedCommits.Location = New-Object System.Drawing.Point(28,409)
$listPushedCommits.Size = New-Object System.Drawing.Size(782,120)
$listPushedCommits.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$listPushedCommits.BackColor = [System.Drawing.SystemColors]::Window
$listPushedCommits.ForeColor = [System.Drawing.SystemColors]::WindowText
$listPushedCommits.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
$form.Controls.Add($listPushedCommits)

$btnDeleteCommit = New-Object System.Windows.Forms.Button
$btnDeleteCommit.Text = '최근 커밋 되돌리기'
$btnDeleteCommit.Location = New-Object System.Drawing.Point(610,204)
$btnDeleteCommit.Size = New-Object System.Drawing.Size(200,32)
$btnDeleteCommit.Enabled = $false
$form.Controls.Add($btnDeleteCommit)

$btnChangedFiles = New-Object System.Windows.Forms.Button
$btnChangedFiles.Text = '변경 파일 보기'
$btnChangedFiles.Location = New-Object System.Drawing.Point(400,204)
$btnChangedFiles.Size = New-Object System.Drawing.Size(190,32)
$btnChangedFiles.Enabled = $false
$form.Controls.Add($btnChangedFiles)

$lblBranch = New-Object System.Windows.Forms.Label
$lblBranch.Text = 'Feature branch 이름'
$lblBranch.AutoSize = $true
$lblBranch.Location = New-Object System.Drawing.Point(28,549)
$form.Controls.Add($lblBranch)

$txtBranch = New-Object System.Windows.Forms.TextBox
$txtBranch.Location = New-Object System.Drawing.Point(28,573)
$txtBranch.Size = New-Object System.Drawing.Size(500,28)
$txtBranch.BackColor = [System.Drawing.SystemColors]::Window
$txtBranch.ForeColor = [System.Drawing.SystemColors]::WindowText
$txtBranch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($txtBranch)

$groupAfter = New-Object System.Windows.Forms.GroupBox
$groupAfter.Text = '머지 후 feature 브랜치'
$groupAfter.Location = New-Object System.Drawing.Point(550,549)
$groupAfter.Size = New-Object System.Drawing.Size(260,78)
$groupAfter.BackColor = [System.Drawing.SystemColors]::Control
$groupAfter.ForeColor = [System.Drawing.SystemColors]::ControlText
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
$btnRun.Location = New-Object System.Drawing.Point(28,622)
$btnRun.Size = New-Object System.Drawing.Size(500,42)
$btnRun.Enabled = $false
$form.Controls.Add($btnRun)

$btnCreateBranch = New-Object System.Windows.Forms.Button
$btnCreateBranch.Text = '현재 커밋에서 브랜치 생성'
$btnCreateBranch.Location = New-Object System.Drawing.Point(28,677)
$btnCreateBranch.Size = New-Object System.Drawing.Size(245,42)
$btnCreateBranch.Enabled = $false
$form.Controls.Add($btnCreateBranch)

$btnMergeDevelop = New-Object System.Windows.Forms.Button
$btnMergeDevelop.Text = '현재 브랜치를 기본 브랜치에 병합'
$btnMergeDevelop.Location = New-Object System.Drawing.Point(283,677)
$btnMergeDevelop.Size = New-Object System.Drawing.Size(527,42)
$btnMergeDevelop.Enabled = $false
$btnMergeDevelop.Tag = 'Blocked'
$form.Controls.Add($btnMergeDevelop)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = '업데이트 확인'
$btnUpdate.Location = New-Object System.Drawing.Point(260,18)
$btnUpdate.Size = New-Object System.Drawing.Size(150,34)
$btnUpdate.Font = New-Object System.Drawing.Font('Malgun Gothic',9,[System.Drawing.FontStyle]::Regular)
$form.Controls.Add($btnUpdate)

$lblBaseBranch = New-Object System.Windows.Forms.Label
$lblBaseBranch.Text = '기본 브랜치'
$lblBaseBranch.AutoSize = $true
$lblBaseBranch.Location = New-Object System.Drawing.Point(430,24)
$form.Controls.Add($lblBaseBranch)

$cmbBaseBranch = New-Object System.Windows.Forms.ComboBox
$cmbBaseBranch.Location = New-Object System.Drawing.Point(530,19)
$cmbBaseBranch.Size = New-Object System.Drawing.Size(280,28)
$cmbBaseBranch.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$form.Controls.Add($cmbBaseBranch)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = '진행 로그'
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(28,742)
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(28,767)
$txtLog.Size = New-Object System.Drawing.Size(782,150)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtLog.BackColor = [System.Drawing.SystemColors]::Window
$txtLog.ForeColor = [System.Drawing.SystemColors]::WindowText
$form.Controls.Add($txtLog)

# Keep the fixed controls aligned while sharing additional window height between
# the commit list and the log.  This makes both areas show more rows when the
# user enlarges the window instead of leaving unused space at the bottom.
$layoutBaseClientSize = $null
$layoutBaseBounds = @{}
$layoutControls = @(
    $txtRepo,$btnAddFavorite,$btnRemoveFavorite,$btnBrowse,$btnRefresh,$lblStatus,
    $lblCommitCount,$listCommits,$btnDeleteCommit,$btnChangedFiles,$lblBranch,
    $lblPushedCommits,$listPushedCommits,$txtBranch,$groupAfter,$btnRun,$btnCreateBranch,$btnMergeDevelop,$lblLog,$txtLog
)

function Initialize-MainWindowLayout {
    $script:layoutBaseClientSize = $form.ClientSize
    $script:layoutBaseBounds.Clear()
    foreach ($control in $layoutControls) {
        $script:layoutBaseBounds[$control.Name + ':' + $control.GetHashCode()] = $control.Bounds
    }
    Update-TopControlsLayout
}

function Get-LayoutBaseBounds($Control) {
    return $layoutBaseBounds[$Control.Name + ':' + $Control.GetHashCode()]
}

function Set-ControlBounds($Control, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    $Control.Bounds = New-Object System.Drawing.Rectangle($X,$Y,[Math]::Max(1,$Width),[Math]::Max(1,$Height))
}

function Update-TopControlsLayout {
    # Use the controls' actual scaled bounds instead of fixed coordinates so
    # high-DPI text never overlaps or clips the controls that follow it.
    $gap = 14
    $btnUpdate.Left = $lblTitle.Right + $gap
    $lblBaseBranch.Left = $btnUpdate.Right + $gap
    $lblBaseBranch.Top = $btnUpdate.Top + [int](($btnUpdate.Height - $lblBaseBranch.Height) / 2)
    $cmbBaseBranch.Left = $lblBaseBranch.Right + $gap
    $availableWidth = $form.ClientSize.Width - $cmbBaseBranch.Left - 34
    $cmbBaseBranch.Width = [Math]::Max(160, $availableWidth)
    if ($cmbBaseBranch.DropDownWidth -lt $cmbBaseBranch.Width) { $cmbBaseBranch.DropDownWidth = $cmbBaseBranch.Width }
}

function Update-MainWindowLayout {
    if ($null -eq $layoutBaseClientSize) { return }
    Update-TopControlsLayout
    $widthDelta = [Math]::Max(0, $form.ClientSize.Width - $layoutBaseClientSize.Width)
    $heightDelta = [Math]::Max(0, $form.ClientSize.Height - $layoutBaseClientSize.Height)
    $commitGrowth = [int][Math]::Floor($heightDelta / 3)
    $pushedGrowth = [int][Math]::Floor($heightDelta / 3)
    $logGrowth = $heightDelta - $commitGrowth - $pushedGrowth
    $lowerShift = $commitGrowth + $pushedGrowth

    foreach ($control in @($txtRepo,$lblStatus,$listCommits,$listPushedCommits,$txtLog)) {
        $base = Get-LayoutBaseBounds $control
        $height = if ($control -eq $listCommits) { $base.Height + $commitGrowth } elseif ($control -eq $listPushedCommits) { $base.Height + $pushedGrowth } elseif ($control -eq $txtLog) { $base.Height + $logGrowth } else { $base.Height }
        $y = if ($control -eq $listPushedCommits) { $base.Y + $commitGrowth } elseif ($control -eq $txtLog) { $base.Y + $lowerShift } else { $base.Y }
        Set-ControlBounds $control $base.X $y ($base.Width + $widthDelta) $height
    }

    foreach ($control in @($btnAddFavorite,$btnRemoveFavorite,$btnBrowse,$btnRefresh,$btnDeleteCommit,$btnChangedFiles,$groupAfter)) {
        $base = Get-LayoutBaseBounds $control
        Set-ControlBounds $control ($base.X + $widthDelta) ($base.Y + $(if ($control -in @($groupAfter)) { $lowerShift } else { 0 })) $base.Width $base.Height
    }

    $pushedLabelBase = Get-LayoutBaseBounds $lblPushedCommits
    Set-ControlBounds $lblPushedCommits $pushedLabelBase.X ($pushedLabelBase.Y + $commitGrowth) $pushedLabelBase.Width $pushedLabelBase.Height

    foreach ($control in @($lblBranch,$txtBranch,$btnRun,$btnCreateBranch,$btnMergeDevelop,$lblLog)) {
        $base = Get-LayoutBaseBounds $control
        $newWidth = $base.Width
        if ($control -in @($txtBranch,$btnRun,$btnMergeDevelop)) { $newWidth += $widthDelta }
        Set-ControlBounds $control $base.X ($base.Y + $lowerShift) $newWidth $base.Height
    }
}

$form.Add_Resize({ Update-MainWindowLayout })

Set-ModernButtonStyle $btnRun $true
Set-ModernButtonStyle $btnMergeDevelop $true
foreach ($button in @($btnBrowse,$btnRefresh,$btnDeleteCommit,$btnChangedFiles,$btnCreateBranch,$btnUpdate,$btnAddFavorite,$btnRemoveFavorite)) {
    Set-ModernButtonStyle $button $false
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Git 저장소 폴더를 선택하세요.'
    if ($txtRepo.Text -and (Test-Path $txtRepo.Text)) { $dlg.SelectedPath = $txtRepo.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtRepo.Text = $dlg.SelectedPath
        Save-Config $dlg.SelectedPath
        Refresh-View
    }
})

$btnRefresh.Add_Click({ Refresh-View })
$btnAddFavorite.Add_Click({ Add-CurrentRepoFavorite })
$btnRemoveFavorite.Add_Click({ Remove-CurrentRepoFavorite })
$txtRepo.Add_SelectionChangeCommitted({
    if (-not $script:LoadingRepoList -and $txtRepo.SelectedItem) {
        $txtRepo.Text = [string]$txtRepo.SelectedItem
        Save-Config $txtRepo.Text
        Refresh-View
    }
})
$txtRepo.Add_TextChanged({
    if (-not $script:LoadingRepoList -and $txtRepo.Text.Trim() -ne $script:LoadedRepoPath) {
        $listPushedCommits.Items.Clear()
        $script:VisiblePushedCommits = @()
    }
})
$txtRepo.Add_KeyDown({
    param($sender,$eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Refresh-View
        $eventArgs.SuppressKeyPress = $true
    }
})
$txtRepo.Add_Leave({
    $enteredPath = $txtRepo.Text.Trim()
    if ($enteredPath -and $enteredPath -ne $script:LoadedRepoPath) { Refresh-View }
})
$btnRun.Add_Click({ Run-Workflow })
$btnDeleteCommit.Add_Click({ Undo-LastCommit })
$btnChangedFiles.Add_Click({ Show-SelectedChangedFiles })
$listPushedCommits.Add_SelectedIndexChanged({ if ($listPushedCommits.SelectedIndices.Count -gt 0) { $listCommits.ClearSelected() } })
$listCommits.Add_SelectedIndexChanged({ if ($listCommits.SelectedIndices.Count -gt 0) { $listPushedCommits.ClearSelected() } })
$btnCreateBranch.Add_Click({ New-BranchAtHead })
$btnMergeDevelop.Add_Click({ Merge-CurrentBranchToDevelop })
$btnUpdate.Add_Click({ Check-ForUpdate $true })
$cmbBaseBranch.Add_SelectionChangeCommitted({
    if (-not $script:LoadingBaseBranch -and $script:LoadedRepoPath -and $cmbBaseBranch.SelectedItem) {
        $script:BaseBranches[$script:LoadedRepoPath] = [string]$cmbBaseBranch.SelectedItem
        Save-Config $script:LoadedRepoPath
        Refresh-View
    }
})

$savedRepo = Load-Config
if ($savedRepo -and (Test-Path $savedRepo)) {
    Sync-FavoriteRepoControl $savedRepo
} else {
    Sync-FavoriteRepoControl (Get-Location).Path
}

$form.Add_Shown({
    Initialize-MainWindowLayout
    if (Ensure-Git) {
        Refresh-View
    } else {
        $lblStatus.Text = 'Git을 사용할 수 없습니다. 설치 상태를 확인해 주세요.'
    }
    $form.BeginInvoke([Action]{ Check-ForUpdate $false }) | Out-Null
})
[void]$form.ShowDialog()
