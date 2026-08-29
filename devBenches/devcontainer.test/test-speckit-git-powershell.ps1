#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [switch]$WindowsStateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GIT_MASTER = '1'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$sourceTemplateRoot = Join-Path $repoRoot 'devBenches/base-image/files/speckit-worktree/templates'
$templateRoot = if ([string]::IsNullOrWhiteSpace($env:SPECKIT_WORKTREE_TEMPLATE_ROOT)) {
    $sourceTemplateRoot
} else {
    $env:SPECKIT_WORKTREE_TEMPLATE_ROOT
}
if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
    $templateRoot = '/usr/local/share/speckit-worktree/templates'
}

$sourceScriptRoot = Join-Path $templateRoot 'specify/extensions/git/scripts/powershell'
$sourceFeatureScript = Join-Path $sourceScriptRoot 'create-new-feature.ps1'
$sourceCommonScript = Join-Path $sourceScriptRoot 'git-common.ps1'
$sourceBashScriptRoot = Join-Path $templateRoot 'specify/extensions/git/scripts/bash'
$sourceBashFeatureScript = Join-Path $sourceBashScriptRoot 'create-new-feature.sh'
$sourceBashCommonScript = Join-Path $sourceBashScriptRoot 'git-common.sh'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) "speckit-git-powershell.$([guid]::NewGuid().ToString('N'))"

$requiredScripts = @($sourceFeatureScript, $sourceCommonScript)
if (-not $WindowsStateOnly) {
    $requiredScripts += @($sourceBashFeatureScript, $sourceBashCommonScript)
}
foreach ($requiredScript in $requiredScripts) {
    if (-not (Test-Path -LiteralPath $requiredScript -PathType Leaf)) {
        throw "Speckit Git PowerShell template is missing: $requiredScript"
    }
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [string]$Label
    )

    if ($Expected -ne $Actual) {
        throw "assertion failed: $Label (expected '$Expected', got '$Actual')"
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Label
    )

    if (-not $Condition) {
        throw "assertion failed: $Label"
    }
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$ExpectedText,
        [string]$Label
    )

    if (-not $Text.Contains($ExpectedText, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "assertion failed: $Label (missing '$ExpectedText')"
    }
}

function Get-GitObjectHash {
    param(
        [string]$Repository,
        [string]$Value
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $Repository
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.ArgumentList.Add('hash-object')
    $startInfo.ArgumentList.Add('--stdin')

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "git hash-object --stdin failed in '$Repository': $stderr"
        }
        return $stdout.TrimEnd("`r", "`n")
    } finally {
        $process.Dispose()
    }
}

function Get-NumberReservationRefs {
    param([string]$Repository)

    return Invoke-GitText -Repository $Repository -Arguments @(
        'for-each-ref',
        '--format=%(refname)',
        'refs/speckit/number-reservations/v1'
    )
}

function Install-NumberReservationGitShim {
    param([string]$Directory)

    [System.IO.Directory]::CreateDirectory($Directory) | Out-Null
    $shimPath = Join-Path $Directory 'git'
    $shim = @'
#!/usr/bin/env bash
real_git() {
    GIT_MASTER=1 "$SPECKIT_TEST_REAL_GIT" "$@"
}

reservation_ref=""
if [ "${1:-}" = update-ref ]; then
    if [ "${2:-}" = -d ]; then
        reservation_ref="${3:-}"
    else
        reservation_ref="${2:-}"
    fi
    case "$reservation_ref" in
        refs/speckit/number-reservations/v1/*)
            if [ -n "${SPECKIT_TEST_RESERVATION_LOG:-}" ]; then
                printf '%s\n' "$*" >> "$SPECKIT_TEST_RESERVATION_LOG"
            fi
            if [ "${SPECKIT_TEST_GIT_MODE:-}" = fail-reservation-create ] \
                && [ "${2:-}" != -d ]; then
                printf 'forced unrelated update-ref failure\n' >&2
                exit 73
            fi
            if [ "${SPECKIT_TEST_GIT_MODE:-}" = fail-reservation-delete-once ] \
                && [ "${2:-}" = -d ] \
                && [ ! -e "$SPECKIT_TEST_DELETE_FAILURE_MARKER" ]; then
                : > "$SPECKIT_TEST_DELETE_FAILURE_MARKER"
                printf 'forced reservation delete failure\n' >&2
                exit 74
            fi
            if [ "${SPECKIT_TEST_GIT_MODE:-}" = replace-reservation-owner ] \
                && [ "${2:-}" = -d ] \
                && [ ! -e "$SPECKIT_TEST_OWNER_REPLACEMENT_MARKER" ]; then
                real_git update-ref "$reservation_ref" "$SPECKIT_TEST_OTHER_OID" "${4:-}" || exit $?
                : > "$SPECKIT_TEST_OWNER_REPLACEMENT_MARKER"
            fi
            if [ "${SPECKIT_TEST_GIT_MODE:-}" = released-reservation-interleaving ]; then
                case "$reservation_ref" in
                    */002)
                        if [ "${SPECKIT_TEST_CREATOR_ROLE:-}" = delayed ] \
                            && [ "${2:-}" != -d ]; then
                            : > "$SPECKIT_TEST_RELEASE_GATE_READY_DIR/$SPECKIT_TEST_CREATOR_ID"
                            cat "$SPECKIT_TEST_RELEASE_GATE" >/dev/null
                        elif [ "${SPECKIT_TEST_CREATOR_ROLE:-}" = publisher ] \
                            && [ "${2:-}" = -d ]; then
                            real_git "$@" || exit $?
                            : > "$SPECKIT_TEST_RELEASE_MARKER"
                            printf x > "$SPECKIT_TEST_RELEASE_GATE"
                            exit 0
                        fi
                        ;;
                esac
            fi
            ;;
    esac
fi

case "${SPECKIT_TEST_GIT_MODE:-}" in
    branch-snapshot-barrier|released-reservation-interleaving)
        if [ "${1:-}" = branch ] && [ "${2:-}" = -a ]; then
            snapshot="$SPECKIT_TEST_BARRIER_DIR/snapshots/$SPECKIT_TEST_CREATOR_ID"
            arrival="$SPECKIT_TEST_BARRIER_DIR/arrivals/$SPECKIT_TEST_CREATOR_ID"
            gate="$SPECKIT_TEST_BARRIER_DIR/gates/$SPECKIT_TEST_CREATOR_ID"
            if [ -e "$arrival" ]; then
                exec env GIT_MASTER=1 "$SPECKIT_TEST_REAL_GIT" "$@"
            fi
            real_git "$@" > "$snapshot" || exit $?
            : > "$arrival"
            if [ -n "${SPECKIT_TEST_BRANCH_GATE_READY_DIR:-}" ]; then
                exec 3< "$gate"
                : > "$SPECKIT_TEST_BRANCH_GATE_READY_DIR/$SPECKIT_TEST_CREATOR_ID"
                cat <&3 >/dev/null
            else
                cat "$gate" >/dev/null
            fi
            cat "$snapshot"
            exit $?
        fi
        ;;
esac

exec env GIT_MASTER=1 "$SPECKIT_TEST_REAL_GIT" "$@"
'@
    [System.IO.File]::WriteAllText($shimPath, $shim.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::SetUnixFileMode(
        $shimPath,
        [System.IO.UnixFileMode]::UserRead -bor
            [System.IO.UnixFileMode]::UserWrite -bor
            [System.IO.UnixFileMode]::UserExecute
    )
    return $shimPath
}

function New-TestFifo {
    param([string]$Path)

    & mkfifo -- $Path
    if ($LASTEXITCODE -ne 0) {
        throw "mkfifo failed for '$Path'"
    }
    return [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::ReadWrite
    )
}

function Wait-ForBarrierFiles {
    param(
        [string]$Directory,
        [int]$ExpectedCount,
        [int]$TimeoutSeconds = 30
    )

    $watcher = [System.IO.FileSystemWatcher]::new($Directory)
    $watcher.Filter = '*'
    $watcher.EnableRaisingEvents = $true
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    try {
        while ([System.IO.Directory]::GetFiles($Directory).Count -lt $ExpectedCount) {
            $remaining = $deadline - [DateTime]::UtcNow
            if ($remaining -le [TimeSpan]::Zero) {
                throw "timed out waiting for barrier files in '$Directory'"
            }
            $change = $watcher.WaitForChanged(
                [System.IO.WatcherChangeTypes]::Created -bor [System.IO.WatcherChangeTypes]::Renamed,
                [Math]::Max(1, [int]$remaining.TotalMilliseconds)
            )
            if ($change.TimedOut) {
                throw "timed out waiting for barrier files in '$Directory'"
            }
        }
    } finally {
        $watcher.Dispose()
    }
}

function Open-TestFifoGate {
    param([System.IO.FileStream]$Stream)

    try {
        $Stream.WriteByte(1)
        $Stream.Flush()
    } finally {
        $Stream.Dispose()
    }
}

function Start-FeatureProcess {
    param(
        [string]$Repository,
        [string]$Description,
        [hashtable]$Environment
    )

    $script = Join-Path $Repository '.specify/extensions/git/scripts/powershell/create-new-feature.ps1'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $Repository
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $script, '-Json', $Description)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment.Remove('GIT_BRANCH_NAME') | Out-Null
    $startInfo.Environment['GIT_MASTER'] = '1'
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    return [PSCustomObject]@{
        Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
        Completed = $false
        OutputFormat = 'Json'
    }
}

function Start-BashFeatureProcess {
    param(
        [string]$Repository,
        [string]$Description,
        [hashtable]$Environment
    )

    $script = Join-Path $Repository '.specify/extensions/git/scripts/bash/create-new-feature.sh'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command bash -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $Repository
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($argument in @($script, $Description)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment.Remove('GIT_BRANCH_NAME') | Out-Null
    $startInfo.Environment['GIT_MASTER'] = '1'
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    return [PSCustomObject]@{
        Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
        Completed = $false
        OutputFormat = 'Text'
    }
}

function Complete-FeatureProcess {
    param(
        $Invocation,
        [int]$TimeoutSeconds = 60
    )

    $process = $Invocation.Process
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            $timeoutStdout = $Invocation.Stdout.GetAwaiter().GetResult()
            $timeoutStderr = $Invocation.Stderr.GetAwaiter().GetResult()
            throw "timed out waiting for feature creator process $($process.Id): stdout='$($timeoutStdout.Trim())' stderr='$($timeoutStderr.Trim())'"
        }
        $stdout = $Invocation.Stdout.GetAwaiter().GetResult()
        $stderr = $Invocation.Stderr.GetAwaiter().GetResult()
        $json = $null
        if ($process.ExitCode -eq 0) {
            if ($Invocation.OutputFormat -eq 'Json') {
                $json = $stdout | ConvertFrom-Json
            } else {
                $fields = [ordered]@{}
                foreach ($line in $stdout -split '\r?\n') {
                    if ($line -match '^(?<key>[A-Z_]+): (?<value>.*)$') {
                        $fields[$matches['key']] = $matches['value']
                    }
                }
                $fields['HAS_GIT'] = $fields['HAS_GIT'] -eq 'true'
                $json = [PSCustomObject]$fields
            }
        }
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Json = $json
            Stdout = $stdout
            Stderr = $stderr
        }
    } finally {
        $Invocation.Completed = $true
        $process.Dispose()
    }
}

function Stop-PendingFeatureProcesses {
    param([object[]]$Invocations)

    foreach ($invocation in $Invocations) {
        if ($null -eq $invocation -or $invocation.Completed) {
            continue
        }
        try {
            if (-not $invocation.Process.HasExited) {
                $invocation.Process.Kill($true)
                $invocation.Process.WaitForExit()
            }
        } finally {
            $invocation.Completed = $true
            $invocation.Process.Dispose()
        }
    }
}

function Get-WindowsAclSddl {
    param([string]$LiteralPath)

    if (-not $IsWindows) {
        return $null
    }
    return (Get-Acl -LiteralPath $LiteralPath).Sddl
}

function Assert-WindowsCurrentUserOnlyFileAcl {
    param(
        [string]$LiteralPath,
        [string]$Label
    )

    if (-not $IsWindows) {
        return
    }

    $acl = Get-Acl -LiteralPath $LiteralPath
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    Assert-Equal $currentUser.Value $owner.Value "$Label owner"
    Assert-True $acl.AreAccessRulesProtected "$Label DACL is protected"
    Assert-Equal 1 $rules.Count "$Label access-rule count"
    $rule = $rules[0]
    Assert-Equal $currentUser.Value $rule.IdentityReference.Value "$Label rule principal"
    Assert-Equal ([System.Security.AccessControl.AccessControlType]::Allow) $rule.AccessControlType "$Label rule type"
    Assert-Equal ([System.Security.AccessControl.FileSystemRights]::FullControl) $rule.FileSystemRights "$Label rule rights"
    Assert-Equal ([System.Security.AccessControl.InheritanceFlags]::None) $rule.InheritanceFlags "$Label inheritance"
    Assert-Equal ([System.Security.AccessControl.PropagationFlags]::None) $rule.PropagationFlags "$Label propagation"
    Assert-True (-not $rule.IsInherited) "$Label rule is explicit"
}

function Invoke-GitText {
    param(
        [string]$Repository,
        [string[]]$Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-C')
    $startInfo.ArgumentList.Add($Repository)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments -join ' ') failed in '$Repository': $stderr"
        }
        return $stdout.TrimEnd("`r", "`n")
    } finally {
        $process.Dispose()
    }
}

function ConvertFrom-TestGitCQuotedPath {
    param([string]$Value)

    if ($Value.Length -lt 2 -or $Value[0] -ne '"' -or $Value[$Value.Length - 1] -ne '"' -or $Value -notmatch '\\(?:[abtnvfr\\"]|[0-7]{1,3})') {
        return $Value
    }

    $content = $Value.Substring(1, $Value.Length - 2)
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $index = 0
    while ($index -lt $content.Length) {
        if ($content[$index] -ne '\') {
            $literalStart = $index
            while ($index -lt $content.Length -and $content[$index] -ne '\') {
                $index++
            }
            $bytes.AddRange([System.Text.Encoding]::UTF8.GetBytes($content.Substring($literalStart, $index - $literalStart)))
            continue
        }

        $index++
        if ($index -ge $content.Length) {
            throw "Malformed Git C-quoted path: trailing escape"
        }
        $escape = $content[$index]
        $simpleEscapes = @{
            'a' = 7; 'b' = 8; 't' = 9; 'n' = 10; 'v' = 11; 'f' = 12; 'r' = 13
            '\' = 92; '"' = 34
        }
        if ($simpleEscapes.ContainsKey([string]$escape)) {
            $bytes.Add([byte]$simpleEscapes[[string]$escape])
            $index++
            continue
        }
        if ($escape -lt '0' -or $escape -gt '7') {
            throw "Malformed Git C-quoted path: unsupported escape \$escape"
        }

        $octal = 0
        $digits = 0
        while ($digits -lt 3 -and $index -lt $content.Length -and $content[$index] -ge '0' -and $content[$index] -le '7') {
            $octal = ($octal * 8) + ([int]$content[$index] - [int][char]'0')
            $digits++
            $index++
        }
        $bytes.Add([byte]$octal)
    }

    return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes.ToArray())
}

function Invoke-GitWorktreePorcelain {
    param(
        [string]$Repository,
        [switch]$NullDelimited
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $Repository
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $arguments = @('worktree', 'list', '--porcelain')
    if ($NullDelimited) {
        $arguments += '-z'
    }
    foreach ($argument in $arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [PSCustomObject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
    } finally {
        $process.Dispose()
    }
}

function Get-RegisteredWorktreePaths {
    param([string]$Repository)

    $result = Invoke-GitWorktreePorcelain -Repository $Repository -NullDelimited
    if ($result.ExitCode -eq 0) {
        return @($result.Stdout.Split([char]0) | Where-Object { $_.StartsWith('worktree ', [System.StringComparison]::Ordinal) } | ForEach-Object { $_.Substring(9) })
    }
    if ($result.ExitCode -ne 129) {
        throw "git worktree list failed in '$Repository': $($result.Stderr)"
    }

    $result = Invoke-GitWorktreePorcelain -Repository $Repository
    if ($result.ExitCode -ne 0) {
        throw "git worktree list failed in '$Repository': $($result.Stderr)"
    }
    $recordPattern = '(?ms)^worktree (?<path>.*?)\r?\nHEAD [0-9a-f]{40,64}\r?\nbranch refs/heads/(?<branch>[^\r\n]+)'
    return @([regex]::Matches($result.Stdout, $recordPattern) | ForEach-Object { ConvertFrom-TestGitCQuotedPath -Value $_.Groups['path'].Value })
}

function Initialize-Fixture {
    param(
        [string]$Name,
        [string]$Config
    )

    $repository = Join-Path $fixtureRoot $Name
    $scriptDirectory = Join-Path $repository '.specify/extensions/git/scripts/powershell'
    $bashScriptDirectory = Join-Path $repository '.specify/extensions/git/scripts/bash'
    New-Item -ItemType Directory -Force -Path $scriptDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $bashScriptDirectory | Out-Null

    & git init -q -b main $repository
    if ($LASTEXITCODE -ne 0) { throw "git init failed for '$repository'" }
    & git -C $repository config user.name 'Spec Kit test'
    if ($LASTEXITCODE -ne 0) { throw "git user.name configuration failed for '$repository'" }
    & git -C $repository config user.email 'spec-kit-test@example.invalid'
    if ($LASTEXITCODE -ne 0) { throw "git user.email configuration failed for '$repository'" }

    Set-Content -LiteralPath (Join-Path $repository '.specify/extensions/git/git-config.yml') -Value $Config -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $repository 'README.md') -Value 'fixture' -Encoding utf8NoBOM
    Copy-Item -LiteralPath $sourceFeatureScript -Destination $scriptDirectory
    Copy-Item -LiteralPath $sourceCommonScript -Destination $scriptDirectory
    Copy-Item -LiteralPath $sourceBashFeatureScript -Destination $bashScriptDirectory
    Copy-Item -LiteralPath $sourceBashCommonScript -Destination $bashScriptDirectory

    & git -C $repository add README.md .specify
    if ($LASTEXITCODE -ne 0) { throw "git add failed for '$repository'" }
    & git -C $repository commit -qm 'fixture commit'
    if ($LASTEXITCODE -ne 0) { throw "git commit failed for '$repository'" }

    return $repository
}

function Invoke-Feature {
    param(
        [string]$Repository,
        [string]$Description,
        [string[]]$Options = @(),
        [AllowNull()][string]$ExactBranch = $null,
        [AllowNull()][string]$WorktreeRoot = $null,
        [hashtable]$Environment = @{}
    )

    $script = Join-Path $Repository '.specify/extensions/git/scripts/powershell/create-new-feature.ps1'
    $stderrFile = Join-Path $fixtureRoot "$([guid]::NewGuid().ToString('N')).stderr"
    $previousExactBranch = [Environment]::GetEnvironmentVariable('GIT_BRANCH_NAME')
    $previousWorktreeRoot = [Environment]::GetEnvironmentVariable('SPECKIT_GIT_WORKTREE_ROOT')
    $previousEnvironment = @{}
    $output = @()
    $exitCode = 0

    try {
        [Environment]::SetEnvironmentVariable('GIT_BRANCH_NAME', $ExactBranch)
        [Environment]::SetEnvironmentVariable('SPECKIT_GIT_WORKTREE_ROOT', $WorktreeRoot)
        foreach ($entry in $Environment.GetEnumerator()) {
            $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value)
        }
        Push-Location $Repository
        try {
            $arguments = @('-NoLogo', '-NoProfile', '-File', $script, '-Json') + $Options + @($Description)
            $output = @(& pwsh @arguments 2> $stderrFile)
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
    } finally {
        [Environment]::SetEnvironmentVariable('GIT_BRANCH_NAME', $previousExactBranch)
        [Environment]::SetEnvironmentVariable('SPECKIT_GIT_WORKTREE_ROOT', $previousWorktreeRoot)
        foreach ($entry in $previousEnvironment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
    }

    $stderr = if (Test-Path -LiteralPath $stderrFile) {
        Get-Content -LiteralPath $stderrFile -Raw
    } else {
        ''
    }

    $json = $null
    if ($exitCode -eq 0) {
        try {
            $json = ($output -join "`n") | ConvertFrom-Json
        } catch {
            throw "feature output was not valid JSON: $($output -join [Environment]::NewLine)"
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Json = $json
        Stderr = $stderr
    }
}

function Get-GitSnapshot {
    param([string]$Repository)

    return [PSCustomObject]@{
        Head = Invoke-GitText -Repository $Repository -Arguments @('rev-parse', 'HEAD')
        Status = Invoke-GitText -Repository $Repository -Arguments @('status', '--porcelain')
        Refs = Invoke-GitText -Repository $Repository -Arguments @('for-each-ref', '--format=%(refname)', 'refs/heads')
        Worktrees = Invoke-GitText -Repository $Repository -Arguments @('worktree', 'list', '--porcelain')
    }
}

function Assert-NoMutation {
    param(
        [string]$Repository,
        $Before,
        [string]$WorktreeRoot,
        [string]$Label
    )

    $after = Get-GitSnapshot -Repository $Repository
    Assert-Equal $Before.Head $after.Head "$Label HEAD"
    Assert-Equal $Before.Status $after.Status "$Label status"
    Assert-Equal $Before.Refs $after.Refs "$Label refs"
    Assert-Equal $Before.Worktrees $after.Worktrees "$Label worktrees"
    Assert-True (-not (Test-Path -LiteralPath $WorktreeRoot)) "$Label worktree root was not created"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repository '.git/speckit-last-worktree.json'))) "$Label state file was not created"
}

function Assert-Worktree {
    param(
        [string]$Repository,
        [string]$ExpectedBranch,
        [string]$ExpectedPath
    )

    Assert-True ([System.IO.Directory]::Exists($ExpectedPath)) "worktree directory exists: $ExpectedPath"
    $actualRoot = Invoke-GitText -Repository $ExpectedPath -Arguments @('rev-parse', '--show-toplevel')
    $actualBranch = Invoke-GitText -Repository $ExpectedPath -Arguments @('branch', '--show-current')
    Assert-Equal $ExpectedPath $actualRoot 'real worktree root'
    Assert-Equal $ExpectedBranch $actualBranch 'real worktree branch'
    Assert-True ((Get-RegisteredWorktreePaths -Repository $Repository) -ccontains $ExpectedPath) 'configured worktree path is registered'
}

function Test-DefaultSequentialWorktree {
    $repository = Initialize-Fixture -Name 'default-sequential' -Config "checkout_mode: worktree`nbase_branch: main"
    $expectedBranch = '001-review-user-access-policy'
    $expectedPath = Join-Path $fixtureRoot "default-sequential-worktrees/$expectedBranch"
    $result = Invoke-Feature -Repository $repository -Description "Review the user's access policy"

    Assert-Equal 0 $result.ExitCode 'default invocation exit code'
    Assert-Equal $expectedBranch $result.Json.BRANCH_NAME 'default BRANCH_NAME'
    Assert-Equal '001' $result.Json.FEATURE_NUM 'default FEATURE_NUM'
    Assert-Equal 'worktree' $result.Json.CHECKOUT_MODE 'default CHECKOUT_MODE'
    Assert-Equal $true $result.Json.HAS_GIT 'default HAS_GIT'
    Assert-Equal 'main' $result.Json.BASE_BRANCH 'default BASE_BRANCH'
    Assert-Equal $expectedPath $result.Json.WORKTREE_PATH 'default WORKTREE_PATH'
    Assert-Worktree -Repository $repository -ExpectedBranch $expectedBranch -ExpectedPath $expectedPath

    $state = Get-Content -LiteralPath (Join-Path $repository '.git/speckit-last-worktree.json') -Raw | ConvertFrom-Json
    Assert-Equal $expectedBranch $state.BRANCH_NAME 'state BRANCH_NAME'
    Assert-Equal $expectedPath $state.WORKTREE_PATH 'state WORKTREE_PATH'
    Assert-WindowsCurrentUserOnlyFileAcl -LiteralPath (Join-Path $repository '.git/speckit-last-worktree.json') -Label 'state file'
    if ($IsWindows) {
        $scratchFiles = @(Get-ChildItem -LiteralPath (Join-Path $repository '.git') -File -Force | Where-Object { $_.Name.StartsWith('.speckit-', [System.StringComparison]::Ordinal) })
        Assert-Equal 0 $scratchFiles.Count 'Windows state capability preflight leaves no scratch file'
    }
}

function Test-NamespacedSequentialNumbering {
    $worktreeRoot = Join-Path $fixtureRoot 'namespace-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../namespace-worktrees`nbranch_prefix: feature/`nbranch_template: {number}-{slug}"
    $repository = Initialize-Fixture -Name 'namespaced' -Config $config
    & git -C $repository branch feature/007-existing
    if ($LASTEXITCODE -ne 0) { throw 'failed to create namespaced fixture branch' }
    & git -C $repository branch other/050-unrelated
    if ($LASTEXITCODE -ne 0) { throw 'failed to create unrelated fixture branch' }

    $expectedBranch = 'feature/008-update-incident-dashboard'
    $expectedPath = Join-Path $worktreeRoot $expectedBranch
    $result = Invoke-Feature -Repository $repository -Description 'Update incident dashboard'

    Assert-Equal 0 $result.ExitCode 'namespaced invocation exit code'
    Assert-Equal $expectedBranch $result.Json.BRANCH_NAME 'namespaced BRANCH_NAME'
    Assert-Equal '008' $result.Json.FEATURE_NUM 'namespaced FEATURE_NUM'
    Assert-Equal $expectedPath $result.Json.WORKTREE_PATH 'namespaced WORKTREE_PATH'
    Assert-Worktree -Repository $repository -ExpectedBranch $expectedBranch -ExpectedPath $expectedPath
}

function Test-RootNumberingIgnoresNamespacedRefs {
    $worktreeRoot = Join-Path $fixtureRoot 'root-numbering-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../root-numbering-worktrees"
    $repository = Initialize-Fixture -Name 'root-numbering' -Config $config
    & git -C $repository branch team/099-other
    if ($LASTEXITCODE -ne 0) { throw 'failed to create namespaced root-numbering fixture branch' }

    $expectedBranch = '001-create-root-feature'
    $expectedPath = Join-Path $worktreeRoot $expectedBranch
    $result = Invoke-Feature -Repository $repository -Description 'Create root feature'

    Assert-Equal 0 $result.ExitCode 'root numbering invocation exit code'
    Assert-Equal $expectedBranch $result.Json.BRANCH_NAME 'root numbering BRANCH_NAME'
    Assert-Equal $expectedPath $result.Json.WORKTREE_PATH 'root numbering WORKTREE_PATH'
    Assert-Worktree -Repository $repository -ExpectedBranch $expectedBranch -ExpectedPath $expectedPath
}

function Test-RepeatedNumberRejectedBeforeMutation {
    $worktreeRoot = Join-Path $fixtureRoot 'repeated-number-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../repeated-number-worktrees`nbranch_template: {number}/{number}-{slug}"
    $repository = Initialize-Fixture -Name 'repeated-number' -Config $config
    $before = Get-GitSnapshot -Repository $repository
    $result = Invoke-Feature -Repository $repository -Description 'Reject repeated number token'

    Assert-True ($result.ExitCode -ne 0) 'repeated {number} invocation fails'
    Assert-Contains $result.Stderr 'exactly one {number}' 'repeated {number} diagnostic'
    Assert-NoMutation -Repository $repository -Before $before -WorktreeRoot $worktreeRoot -Label 'repeated {number} rejection'
}

function Test-UnsupportedTokenRejectedBeforeMutation {
    $worktreeRoot = Join-Path $fixtureRoot 'unsupported-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../unsupported-worktrees`nbranch_template: {number}-{slgu}"
    $repository = Initialize-Fixture -Name 'unsupported-token' -Config $config
    $before = Get-GitSnapshot -Repository $repository
    $result = Invoke-Feature -Repository $repository -Description 'Reject unsupported token'

    Assert-True ($result.ExitCode -ne 0) 'unsupported token invocation fails'
    Assert-Contains $result.Stderr 'unsupported token' 'unsupported token diagnostic'
    Assert-NoMutation -Repository $repository -Before $before -WorktreeRoot $worktreeRoot -Label 'unsupported token rejection'
}

function Test-NegativeNumberRejectedBeforeMutation {
    $worktreeRoot = Join-Path $fixtureRoot 'negative-number-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../negative-number-worktrees"
    $repository = Initialize-Fixture -Name 'negative-number' -Config $config
    $before = Get-GitSnapshot -Repository $repository
    $result = Invoke-Feature -Repository $repository -Description 'Reject negative number' -Options @('-Number', '-1')

    Assert-True ($result.ExitCode -ne 0) 'negative -Number invocation fails'
    Assert-Contains $result.Stderr '-Number must be zero or greater' 'negative -Number diagnostic'
    Assert-NoMutation -Repository $repository -Before $before -WorktreeRoot $worktreeRoot -Label 'negative -Number rejection'
}

function Test-DryRunNonMutation {
    $worktreeRoot = Join-Path $fixtureRoot 'dry-run-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../dry-run-worktrees"
    $repository = Initialize-Fixture -Name 'dry-run' -Config $config
    $before = Get-GitSnapshot -Repository $repository
    $expectedBranch = '001-dry-run-feature'
    $expectedPath = Join-Path $worktreeRoot $expectedBranch
    $result = Invoke-Feature -Repository $repository -Description 'Dry run feature' -Options @('-DryRun')

    Assert-Equal 0 $result.ExitCode 'dry-run invocation exit code'
    Assert-Equal $expectedBranch $result.Json.BRANCH_NAME 'dry-run BRANCH_NAME'
    Assert-Equal $expectedPath $result.Json.WORKTREE_PATH 'dry-run WORKTREE_PATH'
    Assert-Equal $true $result.Json.DRY_RUN 'dry-run DRY_RUN'
    Assert-NoMutation -Repository $repository -Before $before -WorktreeRoot $worktreeRoot -Label 'dry-run'
}

function Test-TruncationRefusesEmptySlug {
    $worktreeRoot = Join-Path $fixtureRoot 'empty-truncation-worktrees'
    $prefix = 'p' * 239
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../empty-truncation-worktrees`nbranch_prefix: $prefix"
    $repository = Initialize-Fixture -Name 'empty-truncation' -Config $config
    $before = Get-GitSnapshot -Repository $repository
    $result = Invoke-Feature -Repository $repository -Description 'Reject empty truncation slug' -Options @('-DryRun', '-ShortName', 'slug')

    Assert-True ($result.ExitCode -ne 0) 'empty-slug truncation invocation fails'
    Assert-Contains $result.Stderr 'truncation removed the feature slug' 'empty-slug truncation diagnostic'
    Assert-NoMutation -Repository $repository -Before $before -WorktreeRoot $worktreeRoot -Label 'empty-slug truncation rejection'
}

function Test-AllowExistingBranchIdempotency {
    $unicodeSuffix = "caf$([char]0x00e9)-$([char]0x96ea)"
    $worktreeRoot = Join-Path $fixtureRoot "idempotent space [literal]-$unicodeSuffix-worktrees"
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../unused-idempotent-worktrees"
    $repository = Initialize-Fixture -Name 'idempotent' -Config $config
    $branch = '001-idempotent-feature'
    $worktreePath = "$worktreeRoot/$branch"
    & git -C $repository worktree add -qb $branch $worktreePath
    if ($LASTEXITCODE -ne 0) { throw 'failed to create special-path idempotency worktree' }
    $beforeCount = @(Get-RegisteredWorktreePaths -Repository $repository).Count
    $second = Invoke-Feature -Repository $repository -Description 'ignored' -Options @('-AllowExistingBranch') -ExactBranch $branch -WorktreeRoot $worktreeRoot
    $afterCount = @(Get-RegisteredWorktreePaths -Repository $repository).Count

    Assert-Equal 0 $second.ExitCode 'allow-existing invocation exit code'
    Assert-Equal $branch $second.Json.BRANCH_NAME 'allow-existing BRANCH_NAME'
    Assert-Equal $worktreePath $second.Json.WORKTREE_PATH 'allow-existing WORKTREE_PATH'
    Assert-Equal $beforeCount $afterCount 'allow-existing worktree count'
    Assert-Worktree -Repository $repository -ExpectedBranch $branch -ExpectedPath $worktreePath
    $state = Get-Content -LiteralPath (Join-Path $repository '.git/speckit-last-worktree.json') -Raw | ConvertFrom-Json
    Assert-Equal $worktreePath $state.WORKTREE_PATH 'allow-existing state WORKTREE_PATH'
}

function Test-GitCQuotedPathDecoder {
    $encoded = '"slash\\quote\"alert\aback\btab\tline\nvertical\vform\freturn\rcaf\303\251-\351\233\252"'
    $expected = "slash\quote`"alert$([char]7)back$([char]8)tab`tline`nvertical$([char]11)form`freturn`rcaf$([char]0x00e9)-$([char]0x96ea)"
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production decoder parse errors'
    $decoderAst = $scriptAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'ConvertFrom-GitCQuotedPath'
    }, $true)
    Assert-True ($null -ne $decoderAst) 'production Git C-quoted decoder exists'
    Invoke-Expression $decoderAst.Extent.Text
    try {
        Assert-Equal $expected (ConvertFrom-GitCQuotedPath -Value $encoded) 'Git C-quoted path decoding'
    } finally {
        Remove-Item Function:\ConvertFrom-GitCQuotedPath -ErrorAction SilentlyContinue
    }
}

function Test-StateReparsePointRejectedBeforeMutation {
    $worktreeRoot = Join-Path $fixtureRoot 'state-reparse-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../state-reparse-worktrees"
    $repository = Initialize-Fixture -Name 'state-reparse' -Config $config
    $stateFile = Join-Path $repository '.git/speckit-last-worktree.json'
    $sentinel = Join-Path $fixtureRoot 'state-reparse-sentinel'
    [System.IO.File]::WriteAllText($sentinel, 'external sentinel bytes', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::CreateSymbolicLink($stateFile, $sentinel) | Out-Null
    $sentinelBefore = [System.IO.File]::ReadAllBytes($sentinel)
    $before = Get-GitSnapshot -Repository $repository

    $result = Invoke-Feature -Repository $repository -Description 'ignored' -ExactBranch '001-state-reparse'

    Assert-True ($result.ExitCode -ne 0) 'reparse-point state invocation fails'
    $after = Get-GitSnapshot -Repository $repository
    Assert-Equal $before.Head $after.Head 'reparse-point rejection HEAD'
    Assert-Equal $before.Status $after.Status 'reparse-point rejection status'
    Assert-Equal $before.Refs $after.Refs 'reparse-point rejection refs'
    Assert-Equal $before.Worktrees $after.Worktrees 'reparse-point rejection worktrees'
    Assert-True (-not (Test-Path -LiteralPath $worktreeRoot)) 'reparse-point rejection worktree root was not created'
    Assert-True (((Get-Item -LiteralPath $stateFile -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'state path remains a reparse point'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual[byte]($sentinelBefore, [System.IO.File]::ReadAllBytes($sentinel))) 'external sentinel bytes remain unchanged'
}

function Test-MalformedRegularStateIsAtomicallyReplaced {
    $worktreeRoot = Join-Path $fixtureRoot 'malformed-state-worktrees'
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../malformed-state-worktrees"
    $repository = Initialize-Fixture -Name 'malformed-state' -Config $config
    $stateFile = Join-Path $repository '.git/speckit-last-worktree.json'
    [System.IO.File]::WriteAllText($stateFile, '{malformed json', [System.Text.UTF8Encoding]::new($false))

    $result = Invoke-Feature -Repository $repository -Description 'ignored' -ExactBranch '001-malformed-state'

    Assert-Equal 0 $result.ExitCode 'malformed regular state recovery exit code'
    $stateBytes = [System.IO.File]::ReadAllBytes($stateFile)
    Assert-True (-not ($stateBytes.Length -ge 3 -and $stateBytes[0] -eq 0xef -and $stateBytes[1] -eq 0xbb -and $stateBytes[2] -eq 0xbf)) 'state JSON has no UTF-8 BOM'
    $state = [System.Text.UTF8Encoding]::new($false, $true).GetString($stateBytes) | ConvertFrom-Json
    Assert-Equal '001-malformed-state' $state.BRANCH_NAME 'recovered state BRANCH_NAME'
    if (-not $IsWindows) {
        Assert-Equal ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite) ([System.IO.File]::GetUnixFileMode($stateFile)) 'state file owner-only permissions'
    }
    Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $repository '.git') -Filter '.speckit-last-worktree.json.tmp.*' -Force).Count 'state temporary cleanup'
}

function Get-StateWriterDefinitions {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production state writer parse errors'
    $functionNames = @('Assert-StateFileSafe', 'Initialize-SafeStateNativeApi', 'Write-LastWorktreeState')
    $definitions = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -ccontains $node.Name
    }, $true))
    Assert-Equal $functionNames.Count $definitions.Count 'production state writer helper count'
    return $definitions
}

function Get-CSharpMemberExtent {
    param(
        [string]$Source,
        [string]$SignaturePattern,
        [string]$Label
    )

    $signature = [regex]::Match($Source, $SignaturePattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    Assert-True $signature.Success "$Label signature exists"
    $openingBrace = $Source.IndexOf('{', $signature.Index + $signature.Length)
    Assert-True ($openingBrace -ge 0) "$Label body starts"
    $depth = 0
    for ($index = $openingBrace; $index -lt $Source.Length; $index++) {
        if ($Source[$index] -eq '{') {
            $depth++
        } elseif ($Source[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Source.Substring($signature.Index, $index - $signature.Index + 1)
            }
        }
    }
    throw "assertion failed: $Label body ends"
}

function Assert-WindowsStatePublicationUsesHeldHandles {
    $writerDefinition = Get-StateWriterDefinitions | Where-Object { $_.Name -ceq 'Write-LastWorktreeState' }
    $writer = $writerDefinition.Extent.Text
    $source = Get-Content -LiteralPath $sourceFeatureScript -Raw
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production transaction lifecycle parse errors'
    Assert-True (-not $writer.Contains('[System.IO.File]::Move(', [System.StringComparison]::Ordinal)) 'Windows state publication does not call path-based File.Move after BeforePublish'
    Assert-True (-not $writer.Contains('Remove-Item -LiteralPath $tempFile', [System.StringComparison]::Ordinal)) 'Windows state cleanup does not remove the temporary by path'
    Assert-True ($source.Contains('NtCreateFile(', [System.StringComparison]::Ordinal)) 'Windows state temporary uses relative NtCreateFile'
    Assert-True ($source.Contains('FileRenameInfoEx', [System.StringComparison]::Ordinal)) 'Windows state publication uses FileRenameInfoEx'
    Assert-True ($source.Contains('FileDispositionInfoEx', [System.StringComparison]::Ordinal)) 'Windows state cleanup uses FileDispositionInfoEx'
    Assert-True ($source.Contains('DangerousAddRef(', [System.StringComparison]::Ordinal)) 'Windows borrowed native handles are protected by DangerousAddRef'
    Assert-True ($source.Contains('public static void AssertSupported(string parentPath)', [System.StringComparison]::Ordinal)) 'Windows state transaction exposes a public support assertion'
    Assert-True ($source.Contains('AssertSupported(parentPath);', [System.StringComparison]::Ordinal)) 'Windows state transaction constructor defensively checks support'
    Assert-True ($source.Contains('Environment.OSVersion.Version.CompareTo(new Version(6, 2)) < 0', [System.StringComparison]::Ordinal)) 'Windows state support requires Windows 8 or later for FILE_ID_INFO'
    Assert-True ($source.Contains('GetDriveTypeW(root)', [System.StringComparison]::Ordinal)) 'Windows state support checks the Git common-directory drive type'
    foreach ($unsupportedDriveType in @('DriveUnknown', 'DriveNoRootDirectory', 'DriveRemote')) {
        Assert-True ($source.Contains($unsupportedDriveType, [System.StringComparison]::Ordinal)) "Windows state support rejects $unsupportedDriveType"
    }
    foreach ($unsupportedError in @('ErrorInvalidFunction = 1', 'ErrorNotSupported = 50', 'ErrorInvalidParameter = 87', 'ErrorCallNotImplemented = 120')) {
        Assert-True ($source.Contains($unsupportedError, [System.StringComparison]::Ordinal)) "Windows EX capability handling includes $unsupportedError"
    }
    Assert-True ($source.Contains('"publish state file"', [System.StringComparison]::Ordinal)) 'production rename identifies FileRenameInfoEx publication failures'
    Assert-True ($source.Contains('ThrowLastWin32WithCapability("clean state temporary", "FileDispositionInfoEx")', [System.StringComparison]::Ordinal)) 'FileDispositionInfoEx capability failures are explicit'
    Assert-True ($source.Contains('new IOException("Windows state publication requires " + capability + " support', [System.StringComparison]::Ordinal)) 'unsupported EX capability throws a clear IOException'
    Assert-True ($source.Contains('reports it as unsupported.", error);', [System.StringComparison]::Ordinal)) 'unsupported EX capability retains the original Win32Exception'

    $stateResolutionIndex = $source.IndexOf('$stateFile = Join-Path $commonDir ''speckit-last-worktree.json''', [System.StringComparison]::Ordinal)
    $preflightSupportIndex = $source.IndexOf('[Speckit.SafeWindowsStateTransaction]::AssertSupported([System.IO.Path]::GetDirectoryName($stateFile))', $stateResolutionIndex, [System.StringComparison]::Ordinal)
    $stateSafetyIndex = $source.IndexOf('Assert-StateFileSafe -LiteralPath $stateFile', $stateResolutionIndex, [System.StringComparison]::Ordinal)
    $worktreeMutationIndex = $source.IndexOf('if (-not $DryRun) {', $stateResolutionIndex, [System.StringComparison]::Ordinal)
    Assert-True ($stateResolutionIndex -ge 0 -and $preflightSupportIndex -gt $stateResolutionIndex -and $preflightSupportIndex -lt $stateSafetyIndex -and $stateSafetyIndex -lt $worktreeMutationIndex) 'Windows support is asserted immediately after state-file resolution and before worktree mutation'

    $transactionAssignments = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Right.Extent.Text.Contains('[Speckit.SafeWindowsStateTransaction]::new(', [System.StringComparison]::Ordinal)
    }, $true) | Where-Object {
        $_.Extent.StartOffset -gt $stateResolutionIndex -and $_.Extent.EndOffset -lt $worktreeMutationIndex
    })
    Assert-Equal 1 $transactionAssignments.Count 'one authenticated Windows state-parent transaction is created before worktree mutation'
    $transactionAssignment = $transactionAssignments[0]
    $transactionVariable = $transactionAssignment.Left.Extent.Text.Trim()
    Assert-True ($transactionVariable -match '^\$[A-Za-z_][A-Za-z0-9_]*$') 'pre-mutation Windows state transaction is retained in a variable'
    $transactionConstruction = $transactionAssignment.Right.Extent.Text
    $usesResolvedStateParent = $transactionConstruction.Contains('[System.IO.Path]::GetDirectoryName($stateFile)', [System.StringComparison]::Ordinal)
    if (-not $usesResolvedStateParent -and $transactionConstruction.Contains('$stateParent', [System.StringComparison]::Ordinal)) {
        $stateParentAssignments = @($scriptAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq '$stateParent' -and
                $node.Right.Extent.Text.Contains('[System.IO.Path]::GetDirectoryName($stateFile)', [System.StringComparison]::Ordinal)
        }, $true) | Where-Object {
            $_.Extent.StartOffset -gt $stateResolutionIndex -and $_.Extent.EndOffset -lt $transactionAssignment.Extent.StartOffset
        })
        $usesResolvedStateParent = $stateParentAssignments.Count -eq 1
    }
    Assert-True $usesResolvedStateParent 'pre-mutation transaction authenticates the resolved state-file parent'

    $writerCalls = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Write-LastWorktreeState'
    }, $true) | Where-Object { $_.Extent.StartOffset -gt $worktreeMutationIndex })
    Assert-Equal 1 $writerCalls.Count 'one post-mutation state publication call exists'
    $writerCall = $writerCalls[0]
    Assert-True ($writerCall.Extent.Text.Contains($transactionVariable, [System.StringComparison]::Ordinal)) 'state publication receives the pre-mutation authenticated parent transaction'
    $lifecycleTryStatements = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.TryStatementAst] -and
            $null -ne $node.Finally -and
            $node.Extent.StartOffset -le $transactionAssignment.Extent.StartOffset -and
            $node.Extent.EndOffset -ge $writerCall.Extent.EndOffset -and
            $node.Finally.Extent.Text.Contains("$transactionVariable.Dispose()", [System.StringComparison]::Ordinal)
    }, $true))
    Assert-Equal 1 $lifecycleTryStatements.Count 'authenticated parent transaction is retained through publication and disposed in finally'

    Assert-True (-not $writer.Contains('[Speckit.SafeWindowsStateTransaction]::new(', [System.StringComparison]::Ordinal)) 'state writer reuses the pre-mutation authenticated parent transaction'
    $writerTransactionParameter = [regex]::Match($writer, '\[Speckit\.SafeWindowsStateTransaction\]\s*\$(?<name>[A-Za-z_][A-Za-z0-9_]*)')
    Assert-True $writerTransactionParameter.Success 'state writer accepts the authenticated parent transaction as a typed parameter'
    $writerTransactionVariable = '$' + $writerTransactionParameter.Groups['name'].Value
    $productionCreate = [regex]::Match($writer, [regex]::Escape($writerTransactionVariable) + '\.(?<method>Create[A-Za-z0-9_]*Temporary[A-Za-z0-9_]*)\s*\(\s*\)')
    Assert-True $productionCreate.Success 'state writer creates the production temporary through the authenticated parent transaction'
    $productionCreateIndex = $productionCreate.Index
    $writeAndFlushIndex = $writer.IndexOf("$writerTransactionVariable.WriteAndFlush(", [System.StringComparison]::Ordinal)
    Assert-True ($productionCreateIndex -ge 0 -and $writeAndFlushIndex -gt $productionCreateIndex) 'production temporary is created after mutation and before bytes are written'

    $classStart = $source.IndexOf('public sealed class SafeWindowsStateTransaction : IDisposable', [System.StringComparison]::Ordinal)
    $classEnd = $source.IndexOf('public static class SafeStateNative', $classStart, [System.StringComparison]::Ordinal)
    Assert-True ($classStart -ge 0 -and $classEnd -gt $classStart) 'Windows state transaction class extent exists'
    $transactionSource = $source.Substring($classStart, $classEnd - $classStart)
    $constructor = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'public\s+SafeWindowsStateTransaction\s*\(\s*string\s+parentPath\s*\)' -Label 'Windows state transaction constructor'
    Assert-True (-not $constructor.Contains('TemporaryName =', [System.StringComparison]::Ordinal)) 'constructor does not create the production temporary before worktree mutation'
    $preflightCall = [regex]::Match($constructor, '(?<method>[A-Za-z_][A-Za-z0-9_]*Preflight[A-Za-z0-9_]*)\s*\((?<arguments>[^)]*)\)\s*;')
    Assert-True $preflightCall.Success 'constructor runs capability preflight against its authenticated parent handle'
    Assert-True ([string]::IsNullOrWhiteSpace($preflightCall.Groups['arguments'].Value) -or $preflightCall.Groups['arguments'].Value.Contains('parentHandle', [System.StringComparison]::Ordinal)) 'constructor preflight uses the transaction authenticated parent handle'
    $preflightName = $preflightCall.Groups['method'].Value
    $preflight = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern ('(?:private|public)\s+(?:static\s+)?void\s+' + [regex]::Escape($preflightName) + '\s*\(') -Label 'Windows state capability preflight'
    $probeCreates = [regex]::Matches($preflight, '(?<handle>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*CreateCapabilityProbe\s*\(\s*parentHandle\s*,\s*"(?<role>source|destination)"\s*,\s*out\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\)')
    Assert-Equal 2 $probeCreates.Count 'capability preflight creates private source and destination scratches'
    $sourceProbe = $probeCreates | Where-Object { $_.Groups['role'].Value -eq 'source' }
    $destinationProbe = $probeCreates | Where-Object { $_.Groups['role'].Value -eq 'destination' }
    Assert-True ($null -ne $sourceProbe -and $null -ne $destinationProbe) 'capability preflight names both replacement roles'
    $sourceHandle = $sourceProbe.Groups['handle'].Value
    $sourceName = $sourceProbe.Groups['name'].Value
    $destinationHandle = $destinationProbe.Groups['handle'].Value
    $destinationName = $destinationProbe.Groups['name'].Value
    $sourceValidationIndex = $preflight.IndexOf("ValidateTemporarySecurity($sourceHandle)", [System.StringComparison]::Ordinal)
    $destinationValidationIndex = $preflight.IndexOf("ValidateTemporarySecurity($destinationHandle)", [System.StringComparison]::Ordinal)
    $renameCall = [regex]::Match($preflight, '(?<method>(?:Rename[A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*Rename[A-Za-z0-9_]*))\s*\(\s*' + [regex]::Escape($sourceHandle) + '\s*,\s*parentHandle\s*,\s*' + [regex]::Escape($destinationName) + '\s*,\s*"replace state capability probe"\s*\)')
    Assert-True ($sourceValidationIndex -gt $sourceProbe.Index -and $destinationValidationIndex -gt $destinationProbe.Index -and $renameCall.Success) 'capability preflight validates both held scratches before replacement'
    Assert-True ($sourceValidationIndex -lt $renameCall.Index -and $destinationValidationIndex -lt $renameCall.Index) 'capability preflight validates both DACLs before replacement'

    $replacementFlag = [regex]::Match($preflight, 'bool\s+(?<name>(?:[A-Za-z_][A-Za-z0-9_]*)?replacement[A-Za-z0-9_]*)\s*=\s*false\s*;', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    Assert-True $replacementFlag.Success 'capability preflight tracks whether replacement succeeded'
    $replacementFlagName = $replacementFlag.Groups['name'].Value
    $replacementSucceededIndex = $preflight.IndexOf("$replacementFlagName = true", $renameCall.Index, [System.StringComparison]::Ordinal)
    Assert-True ($replacementSucceededIndex -gt $renameCall.Index) 'capability preflight records replacement success only after FileRenameInfoEx succeeds'

    $sourceCleanup = [regex]::Match($preflight, 'CleanupProbeHandle\s*\(\s*ref\s+' + [regex]::Escape($sourceHandle) + '\s*,\s*ref\s+[A-Za-z_][A-Za-z0-9_]*\s*,\s*ref\s+cleanupError\s*\)')
    Assert-True ($sourceCleanup.Success -and $sourceCleanup.Index -gt $replacementSucceededIndex) 'capability preflight always dispositions and closes the source handle'
    $replacementCleanupBranch = [regex]::Match($preflight, '(?s)if\s*\(\s*' + [regex]::Escape($replacementFlagName) + '\s*\)\s*\{(?<success>.*?)\}\s*else\s*\{(?<failure>.*?)\}')
    Assert-True $replacementCleanupBranch.Success 'capability preflight branches destination cleanup on replacement success'
    $successfulCleanup = $replacementCleanupBranch.Groups['success'].Value
    $failedCleanup = $replacementCleanupBranch.Groups['failure'].Value
    Assert-True ($successfulCleanup.Contains("CloseProbeHandle(ref $destinationHandle, ref cleanupError)", [System.StringComparison]::Ordinal) -and -not $successfulCleanup.Contains('CleanupProbeHandle(', [System.StringComparison]::Ordinal) -and -not $successfulCleanup.Contains('SetProbeDisposition(', [System.StringComparison]::Ordinal)) 'successful replacement closes the detached old destination without disposition'
    Assert-True ($failedCleanup.Contains("CleanupProbeHandle(ref $destinationHandle", [System.StringComparison]::Ordinal)) 'pre-replacement failure dispositions and closes the still-named destination'
    $sourceAbsenceIndex = $preflight.IndexOf("AssertRelativeMissing(parentHandle, $sourceName)", [System.StringComparison]::Ordinal)
    $destinationAbsenceIndex = $preflight.IndexOf("AssertRelativeMissing(parentHandle, $destinationName)", [System.StringComparison]::Ordinal)
    Assert-True ($sourceAbsenceIndex -gt $renameCall.Index -and $destinationAbsenceIndex -gt $renameCall.Index) 'capability preflight verifies both scratch names absent after held-handle cleanup'

    $renameMember = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern ('(?:private|public)\s+(?:static\s+)?[A-Za-z0-9_<>,\.\[\]]+\s+' + [regex]::Escape($renameCall.Groups['method'].Value) + '\s*\(') -Label 'shared replacement helper'
    Assert-True ($renameMember.Contains('SetFileInformationByHandle(', [System.StringComparison]::Ordinal) -and $renameMember.Contains('FileRenameInfoEx', [System.StringComparison]::Ordinal) -and $renameMember.Contains('FileRenameReplaceIfExists | FileRenamePosixSemantics', [System.StringComparison]::Ordinal)) 'preflight replacement uses production FileRenameInfoEx flags'
    $renameTemporary = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+void\s+RenameTemporary\s*\(' -Label 'production rename wrapper'
    Assert-True ($renameTemporary.Contains($renameCall.Groups['method'].Value + '(temporaryHandle, parentHandle, stateName, "publish state file")', [System.StringComparison]::Ordinal)) 'preflight and publication use the same replacement helper'
    $cleanupMember = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+static\s+void\s+CleanupProbeHandle\s*\(' -Label 'held scratch cleanup helper'
    Assert-True ($cleanupMember.Contains('SetProbeDisposition(', [System.StringComparison]::Ordinal) -and $cleanupMember.Contains('CloseProbeHandle(', [System.StringComparison]::Ordinal) -and -not $cleanupMember.Contains('File.Delete(', [System.StringComparison]::Ordinal)) 'named scratch cleanup uses disposition then held-handle close without pathname fallback'
    $closeMember = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+static\s+void\s+CloseProbeHandle\s*\(' -Label 'detached scratch close helper'
    Assert-True ($closeMember.Contains('Dispose()', [System.StringComparison]::Ordinal) -and -not $closeMember.Contains('SetProbeDisposition(', [System.StringComparison]::Ordinal) -and -not $closeMember.Contains('File.Delete(', [System.StringComparison]::Ordinal)) 'detached destination cleanup closes its held handle without disposition or pathname cleanup'
    $absenceMember = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+static\s+void\s+AssertRelativeMissing\s*\(' -Label 'preflight absence helper'
    Assert-True ($absenceMember.Contains('OpenRelative(', [System.StringComparison]::Ordinal) -and $absenceMember.Contains('StatusObjectNameNotFound', [System.StringComparison]::Ordinal)) 'preflight verifies scratch absence relative to the held parent handle'
    Assert-True ($preflight.Contains('primaryError.Data["WindowsStateCleanupError"] = cleanupError', [System.StringComparison]::Ordinal) -and $preflight.Contains('ExceptionDispatchInfo.Capture(primaryError).Throw()', [System.StringComparison]::Ordinal)) 'preflight surfaces cleanup errors without replacing the original primary exception'

    $productionCreateName = $productionCreate.Groups['method'].Value
    $productionCreateMember = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern ('public\s+void\s+' + [regex]::Escape($productionCreateName) + '\s*\(') -Label 'production temporary creation method'
    $productionRelativeCreate = [regex]::Match($productionCreateMember, 'CreateRelative\s*\(\s*parentHandle\s*,\s*TemporaryName\s*,\s*out\s+temporaryHandle\s*\)')
    Assert-True $productionRelativeCreate.Success 'production temporary is created relative to the same authenticated parent handle'
    $createRelative = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+static\s+int\s+CreateRelative\s*\(' -Label 'relative temporary creation helper'
    $descriptorFactoryCall = [regex]::Match($createRelative, '(?<variable>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<method>(?:Create|Build)[A-Za-z0-9_]*SecurityDescriptor[A-Za-z0-9_]*)\s*\(')
    Assert-True $descriptorFactoryCall.Success 'relative temporary creation builds a creation-time security descriptor'
    $relativeNtCreateCall = [regex]::Match($createRelative, '(?s)NtCreateRelative\s*\((?<arguments>.*?)\)\s*;')
    Assert-True ($relativeNtCreateCall.Success -and $relativeNtCreateCall.Groups['arguments'].Value.Contains($descriptorFactoryCall.Groups['variable'].Value, [System.StringComparison]::Ordinal)) 'relative temporary creation supplies the protected DACL to NtCreateRelative'
    $descriptorFactory = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern ('(?:private|public)\s+(?:static\s+)?[A-Za-z0-9_<>,\.\[\]]+\s+' + [regex]::Escape($descriptorFactoryCall.Groups['method'].Value) + '\s*\(') -Label 'temporary security descriptor factory'
    $descriptorProtectsDacl = $descriptorFactory.Contains('SetAccessRuleProtection(true, false)', [System.StringComparison]::Ordinal) -or $descriptorFactory.Contains('DiscretionaryAclProtected', [System.StringComparison]::Ordinal)
    $descriptorAllowsCurrentUser = $descriptorFactory.Contains('AccessControlType.Allow', [System.StringComparison]::Ordinal) -or $descriptorFactory.Contains('AceQualifier.AccessAllowed', [System.StringComparison]::Ordinal)
    $descriptorGrantsFullControl = $descriptorFactory.Contains('FileSystemRights.FullControl', [System.StringComparison]::Ordinal) -or $descriptorFactory.Contains('FileAllAccess', [System.StringComparison]::Ordinal)
    $descriptorSetsOwner = $descriptorFactory.Contains('SetOwner(', [System.StringComparison]::Ordinal) -or $descriptorFactory.Contains('Owner =', [System.StringComparison]::Ordinal) -or $descriptorFactory.Contains('RawSecurityDescriptor(', [System.StringComparison]::Ordinal)
    Assert-True ($descriptorFactory.Contains('WindowsIdentity.GetCurrent()', [System.StringComparison]::Ordinal) -and $descriptorSetsOwner -and $descriptorProtectsDacl) 'temporary creation descriptor sets the current owner and a protected DACL'
    Assert-True ($descriptorAllowsCurrentUser -and $descriptorGrantsFullControl) 'temporary creation DACL grants only full control to its current-user rule'

    $ntCreateRelative = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+static\s+int\s+NtCreateRelative\s*\(' -Label 'NtCreateRelative helper'
    $securityParameter = [regex]::Match($ntCreateRelative, 'IntPtr\s+(?<name>(?:[A-Za-z_][A-Za-z0-9_]*)?[Ss]ecurityDescriptor[A-Za-z0-9_]*)')
    Assert-True $securityParameter.Success 'NtCreateRelative accepts a creation security descriptor'
    Assert-True ($ntCreateRelative.Contains('SecurityDescriptor = ' + $securityParameter.Groups['name'].Value, [System.StringComparison]::Ordinal)) 'NtCreateRelative assigns the supplied DACL to ObjectAttributes at creation'
    $shareParameter = [regex]::Match($ntCreateRelative, 'uint\s+(?<name>(?:[A-Za-z_][A-Za-z0-9_]*)?shareAccess[A-Za-z0-9_]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    Assert-True $shareParameter.Success 'NtCreateRelative accepts explicit share access'
    Assert-True ([regex]::IsMatch($ntCreateRelative, 'FileAttributeNormal\s*,\s*' + [regex]::Escape($shareParameter.Groups['name'].Value) + '\s*,\s*disposition')) 'NtCreateRelative passes explicit sharing to NtCreateFile'
    Assert-True ([regex]::IsMatch($createRelative, '(?s)NtCreateRelative\s*\(.*?\b0\s*,\s*FileCreate\s*,\s*securityDescriptor')) 'probe and production temporaries are created with ShareAccess=0'
    $openRelative = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'private\s+static\s+int\s+OpenRelative\s*\(' -Label 'relative inspection helper'
    Assert-True ([regex]::IsMatch($openRelative, '(?s)NtCreateRelative\s*\(.*?ShareAll\s*,\s*FileOpen\s*,\s*IntPtr\.Zero')) 'destination inspection and absence verification use ShareAll'

    $securityValidation = [regex]::Match($productionCreateMember, '(?<method>[A-Za-z_][A-Za-z0-9_]*(?:Security|Acl)[A-Za-z0-9_]*)\s*\(\s*temporaryHandle\s*\)\s*;')
    Assert-True $securityValidation.Success 'production temporary security is verified through its held handle'
    Assert-True ($securityValidation.Index -gt $productionRelativeCreate.Index) 'production temporary security is verified after handle-relative creation'
    $securityValidationName = $securityValidation.Groups['method'].Value
    Assert-True ($sourceValidationIndex -gt $sourceProbe.Index -and $sourceValidationIndex -lt $renameCall.Index) 'preflight source security is verified through its held handle before replacement'
    Assert-True ($destinationValidationIndex -gt $destinationProbe.Index -and $destinationValidationIndex -lt $renameCall.Index) 'preflight destination security is verified through its held handle before replacement'
    $securityVerifier = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern ('(?:private|public)\s+(?:static\s+)?void\s+' + [regex]::Escape($securityValidationName) + '\s*\(\s*SafeFileHandle\s+') -Label 'held-handle security verifier'
    Assert-True (-not $securityVerifier.Contains('OpenRelative(', [System.StringComparison]::Ordinal) -and -not $securityVerifier.Contains('CreateFileW(', [System.StringComparison]::Ordinal)) 'temporary security verification does not reopen by path'
    Assert-True ($securityVerifier.Contains('DangerousGetHandle()', [System.StringComparison]::Ordinal) -and $securityVerifier.Contains('GetSecurityInfo(', [System.StringComparison]::Ordinal)) 'temporary security verification queries the held handle'
    Assert-True ($securityVerifier.Contains('Owner', [System.StringComparison]::Ordinal) -and ($securityVerifier.Contains('WindowsIdentity.GetCurrent()', [System.StringComparison]::Ordinal) -or $securityVerifier.Contains('currentUser', [System.StringComparison]::Ordinal))) 'temporary owner is compared with the current user'
    Assert-True ($securityVerifier.Contains('DiscretionaryAclProtected', [System.StringComparison]::Ordinal) -and [regex]::IsMatch($securityVerifier, '(?:\.Count|AceCount)\s*!=\s*1')) 'temporary verifier requires a protected DACL with exactly one ACE'
    $verifierRequiresAllow = $securityVerifier.Contains('AccessControlType.Allow', [System.StringComparison]::Ordinal) -or $securityVerifier.Contains('AceQualifier.AccessAllowed', [System.StringComparison]::Ordinal)
    $verifierRequiresFullControl = $securityVerifier.Contains('FileSystemRights.FullControl', [System.StringComparison]::Ordinal) -or $securityVerifier.Contains('FileAllAccess', [System.StringComparison]::Ordinal)
    $verifierRequiresCurrentUserRule = [regex]::IsMatch($securityVerifier, '(?s)(?:IdentityReference|SecurityIdentifier).*currentUser|currentUser.*(?:IdentityReference|SecurityIdentifier)')
    $verifierRequiresNoInheritance = ($securityVerifier.Contains('InheritanceFlags.None', [System.StringComparison]::Ordinal) -and $securityVerifier.Contains('PropagationFlags.None', [System.StringComparison]::Ordinal)) -or $securityVerifier.Contains('AceFlags.None', [System.StringComparison]::Ordinal)
    Assert-True $verifierRequiresCurrentUserRule 'temporary verifier requires the sole ACE principal to be the current user'
    Assert-True $verifierRequiresNoInheritance 'temporary verifier requires a non-inherited exact access rule'
    Assert-True ($verifierRequiresAllow -and $verifierRequiresFullControl) 'temporary verifier requires the exact current-user full-control rule'

    $publish = Get-CSharpMemberExtent -Source $transactionSource -SignaturePattern 'public\s+void\s+Publish\s*\(' -Label 'Windows state publication method'
    Assert-True (-not $transactionSource.Contains('AuthenticateTemporary', [System.StringComparison]::Ordinal)) 'Windows transaction removes the second-open AuthenticateTemporary pattern'
    Assert-True (-not $publish.Contains('OpenRelative(parentHandle, TemporaryName', [System.StringComparison]::Ordinal)) 'Windows publication never second-opens the production temporary'
    Assert-True ($publish.Contains("$securityValidationName(temporaryHandle)", [System.StringComparison]::Ordinal)) 'Windows publication revalidates security through the original held temporary handle'
}

function Test-WindowsStateTransactionStructure {
    Assert-WindowsStatePublicationUsesHeldHandles

    $heldReaderRegression = ${function:Test-WindowsStateReplacesExistingFileWithHeldReader}.ToString()
    Assert-True ($heldReaderRegression.Contains('[System.IO.FileShare]::Read', [System.StringComparison]::Ordinal) -and $heldReaderRegression.Contains('Write-LastWorktreeState', [System.StringComparison]::Ordinal)) 'native Windows regression holds an ordinary reader while replacing existing state'

    $primaryFailureRegression = ${function:Test-WindowsStatePrimaryFailurePreservesErrorAndCleansTemporary}.ToString()
    Assert-True ($primaryFailureRegression.Contains('$primaryError = $null', [System.StringComparison]::Ordinal) -and $primaryFailureRegression.Contains('$cleanupError = $null', [System.StringComparison]::Ordinal)) 'forced-failure regression captures primary and cleanup errors separately'
    Assert-True ($primaryFailureRegression.Contains('[object]::ReferenceEquals($failureState.ExpectedError, $primaryError)', [System.StringComparison]::Ordinal)) 'forced-failure regression proves the original primary exception remains primary'
    Assert-True ($primaryFailureRegression.Contains('-not (Test-Path -LiteralPath $failureState.TemporaryPath)', [System.StringComparison]::Ordinal)) 'forced-failure regression proves the production temporary is absent after cleanup'

    $temporaryAttackWrapper = ${function:Test-WindowsStateTemporaryLeafReplacementAttack}.ToString()
    Assert-True ($temporaryAttackWrapper.Contains('if (-not $IsWindows)', [System.StringComparison]::Ordinal) -and $temporaryAttackWrapper.Contains('Test-StateTemporaryLeafReplacementAttackCore', [System.StringComparison]::Ordinal)) 'Windows temporary attack selector gates native behavior and invokes the shared attack core'
    $parentSwapWrapper = ${function:Test-WindowsStateAuthenticatedParentSwap}.ToString()
    Assert-True ($parentSwapWrapper.Contains('if (-not $IsWindows)', [System.StringComparison]::Ordinal) -and $parentSwapWrapper.Contains('Test-StateParentSwapPublishesOnlyToAuthenticatedParent', [System.StringComparison]::Ordinal)) 'Windows parent-swap selector gates native behavior and invokes the authenticated-parent regression'

    $defaultStateBundle = ${function:Test-StateTemporaryLeafReplacementFailsClosed}.ToString()
    foreach ($bundledTest in @(
        'Test-WindowsStateTransactionStructure',
        'Test-WindowsStateReplacesExistingFileWithHeldReader',
        'Test-WindowsStatePrimaryFailurePreservesErrorAndCleansTemporary',
        'Test-StateTemporaryLeafReplacementAttackCore'
    )) {
        Assert-True ($defaultStateBundle.Contains($bundledTest, [System.StringComparison]::Ordinal)) "default state scenario bundles $bundledTest exactly once"
        Assert-Equal 1 ([regex]::Matches($defaultStateBundle, [regex]::Escape($bundledTest)).Count) "default state scenario $bundledTest invocation count"
    }
}

function Test-WindowsStateReplacesExistingFileWithHeldReader {
    if (-not $IsWindows) {
        return
    }

    $testRoot = Join-Path $fixtureRoot 'windows-state-held-reader'
    $stateParent = Join-Path $testRoot 'state-parent'
    $statePath = Join-Path $stateParent 'speckit-last-worktree.json'
    [System.IO.Directory]::CreateDirectory($stateParent) | Out-Null
    $previousState = 'trusted previous state'
    [System.IO.File]::WriteAllText($statePath, $previousState, [System.Text.UTF8Encoding]::new($false))
    $definitions = Get-StateWriterDefinitions

    & {
        param($Definitions, $StatePath, $PreviousState)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }
        $script:stateFile = $StatePath
        $script:repoRoot = Split-Path (Split-Path $StatePath -Parent) -Parent
        Initialize-SafeStateNativeApi
        $reader = [System.IO.File]::Open($StatePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $windowsTransaction = $null
        $publicationError = $null
        $cleanupError = $null
        try {
            $windowsTransaction = [Speckit.SafeWindowsStateTransaction]::new([System.IO.Path]::GetDirectoryName($StatePath))
            Write-LastWorktreeState -BranchName '053-held-reader-replacement' -WorktreePath 'C:\worktree' -BaseBranch 'main' -WindowsTransaction $windowsTransaction
        } catch {
            $publicationError = $_.Exception
        } finally {
            if ($null -ne $windowsTransaction) {
                try {
                    $windowsTransaction.Dispose()
                } catch {
                    $cleanupError = $_.Exception
                }
            }
        }

        try {
            Assert-Equal $null $publicationError 'held-reader state replacement publication error'
            Assert-Equal $null $cleanupError 'held-reader state replacement cleanup error'
            $reader.Position = 0
            $readerBytes = [byte[]]::new([int]$reader.Length)
            $readerLength = $reader.Read($readerBytes, 0, $readerBytes.Length)
            Assert-Equal $readerBytes.Length $readerLength 'held reader old-state byte count'
            Assert-Equal $PreviousState ([System.Text.UTF8Encoding]::new($false, $true).GetString($readerBytes)) 'held reader remains attached to previous state'
            $publishedState = [System.IO.File]::ReadAllText($StatePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
            Assert-Equal '053-held-reader-replacement' $publishedState.BRANCH_NAME 'held-reader replacement publishes new state'
            Assert-WindowsCurrentUserOnlyFileAcl -LiteralPath $StatePath -Label 'held-reader replacement state file'
            Assert-Equal 0 @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetDirectoryName($StatePath)) -Filter '.speckit-last-worktree.json.tmp.*' -Force).Count 'held-reader replacement leaves no production temporary'
        } finally {
            $reader.Dispose()
        }
    } $definitions $statePath $previousState
}

function Test-WindowsStatePrimaryFailurePreservesErrorAndCleansTemporary {
    if (-not $IsWindows) {
        return
    }

    $testRoot = Join-Path $fixtureRoot 'windows-state-primary-failure'
    $stateParent = Join-Path $testRoot 'state-parent'
    $statePath = Join-Path $stateParent 'speckit-last-worktree.json'
    [System.IO.Directory]::CreateDirectory($stateParent) | Out-Null
    $previousState = 'trusted previous state'
    [System.IO.File]::WriteAllText($statePath, $previousState, [System.Text.UTF8Encoding]::new($false))
    $definitions = Get-StateWriterDefinitions

    & {
        param($Definitions, $StatePath, $PreviousState)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }
        $script:stateFile = $StatePath
        $script:repoRoot = Split-Path (Split-Path $StatePath -Parent) -Parent
        Initialize-SafeStateNativeApi
        $windowsTransaction = [Speckit.SafeWindowsStateTransaction]::new([System.IO.Path]::GetDirectoryName($StatePath))
        $failureState = [PSCustomObject]@{
            TemporaryPath = $null
            ExpectedError = [System.InvalidOperationException]::new('forced Windows state publication primary failure')
        }
        $forcedFailure = {
            param($TemporaryPath)
            $failureState.TemporaryPath = $TemporaryPath
            throw $failureState.ExpectedError
        }.GetNewClosure()
        $primaryError = $null
        $cleanupError = $null
        try {
            Write-LastWorktreeState -BranchName '054-forced-primary-failure' -WorktreePath 'C:\worktree' -BaseBranch 'main' -BeforePublish $forcedFailure -WindowsTransaction $windowsTransaction
        } catch {
            $primaryError = $_.Exception
        } finally {
            try {
                $windowsTransaction.Dispose()
            } catch {
                $cleanupError = $_.Exception
            }
        }

        Assert-True ([object]::ReferenceEquals($failureState.ExpectedError, $primaryError)) 'forced publication preserves the original primary exception object'
        Assert-Equal $null $cleanupError 'forced publication captures cleanup errors separately'
        Assert-True (-not [string]::IsNullOrWhiteSpace($failureState.TemporaryPath)) 'forced publication observed the production temporary path'
        Assert-True (-not (Test-Path -LiteralPath $failureState.TemporaryPath)) 'forced publication removes the production temporary by held handle'
        Assert-Equal $PreviousState ([System.IO.File]::ReadAllText($StatePath, [System.Text.UTF8Encoding]::new($false, $true))) 'forced publication preserves prior state'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetDirectoryName($StatePath)) -Filter '.speckit-last-worktree.json.tmp.*' -Force).Count 'forced publication leaves no production temporary'
    } $definitions $statePath $previousState
}

function Test-StateTemporaryLeafReplacementAttackCore {
    $testRoot = Join-Path $fixtureRoot 'state-temporary-leaf-replacement'
    $stateParent = Join-Path $testRoot 'state-parent'
    $statePath = Join-Path $stateParent 'speckit-last-worktree.json'
    $sentinelPath = Join-Path $testRoot 'external-sentinel'
    [System.IO.Directory]::CreateDirectory($stateParent) | Out-Null
    [System.IO.File]::WriteAllText($statePath, 'trusted previous state', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($sentinelPath, 'attacker-controlled sentinel', [System.Text.UTF8Encoding]::new($false))
    if (-not $IsWindows) {
        [System.IO.File]::SetUnixFileMode($statePath, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::GroupRead)
        [System.IO.File]::SetUnixFileMode($sentinelPath, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::GroupRead)
    }
    $stateBefore = [System.IO.File]::ReadAllBytes($statePath)
    $sentinelBefore = [System.IO.File]::ReadAllBytes($sentinelPath)
    $stateModeBefore = if ($IsWindows) { $null } else { [System.IO.File]::GetUnixFileMode($statePath) }
    $sentinelModeBefore = if ($IsWindows) { $null } else { [System.IO.File]::GetUnixFileMode($sentinelPath) }
    $stateAclBefore = Get-WindowsAclSddl -LiteralPath $statePath
    $sentinelAclBefore = Get-WindowsAclSddl -LiteralPath $sentinelPath
    $definitions = Get-StateWriterDefinitions

    & {
        param($Definitions, $StatePath, $SentinelPath, $StateBefore, $SentinelBefore, $StateModeBefore, $SentinelModeBefore, $StateAclBefore, $SentinelAclBefore)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }
        $script:stateFile = $StatePath
        $script:repoRoot = Split-Path (Split-Path $StatePath -Parent) -Parent
        Initialize-SafeStateNativeApi
        $windowsTransaction = if ($IsWindows) {
            [Speckit.SafeWindowsStateTransaction]::new([System.IO.Path]::GetDirectoryName($StatePath))
        } else {
            $null
        }
        $script:TemporarySecondOpenBlocked = $null
        $replacement = {
            param($TemporaryPath)
            if ($IsWindows) {
                $script:TemporarySecondOpenBlocked = $false
                $secondOpen = $null
                try {
                    $secondOpen = [System.IO.File]::Open(
                        $TemporaryPath,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
                    )
                } catch [System.IO.IOException] {
                    $script:TemporarySecondOpenBlocked = $true
                } finally {
                    if ($null -ne $secondOpen) {
                        $secondOpen.Dispose()
                    }
                }
            }
            Remove-Item -LiteralPath $TemporaryPath -Force
            New-Item -ItemType HardLink -Path $TemporaryPath -Target $SentinelPath | Out-Null
        }

        $primaryError = $null
        $cleanupError = $null
        try {
            Write-LastWorktreeState -BranchName '051-temporary-replacement' -WorktreePath '/tmp/worktree' -BaseBranch 'main' -BeforePublish $replacement -WindowsTransaction $windowsTransaction
        } catch {
            $primaryError = $_.Exception
        } finally {
            if ($null -ne $windowsTransaction) {
                try {
                    $windowsTransaction.Dispose()
                } catch {
                    $cleanupError = $_.Exception
                }
            }
        }

        Assert-True ($null -ne $primaryError) 'temporary-leaf replacement fails closed'
        Assert-Equal $null $cleanupError 'temporary-leaf replacement captures cleanup errors separately'
        if ($IsWindows) {
            Assert-Equal $true $script:TemporarySecondOpenBlocked 'production state temporary denies a second open while its held handle is live'
        }
        Assert-True ([System.Linq.Enumerable]::SequenceEqual[byte]($StateBefore, [System.IO.File]::ReadAllBytes($StatePath))) 'temporary-leaf replacement preserves prior state bytes'
        Assert-True ([System.Linq.Enumerable]::SequenceEqual[byte]($SentinelBefore, [System.IO.File]::ReadAllBytes($SentinelPath))) 'temporary-leaf replacement preserves external sentinel bytes'
        if (-not $IsWindows) {
            Assert-Equal $StateModeBefore ([System.IO.File]::GetUnixFileMode($StatePath)) 'temporary-leaf replacement preserves prior state mode'
            Assert-Equal $SentinelModeBefore ([System.IO.File]::GetUnixFileMode($SentinelPath)) 'temporary-leaf replacement preserves external sentinel mode'
        } else {
            Assert-Equal $StateAclBefore (Get-WindowsAclSddl -LiteralPath $StatePath) 'temporary-leaf replacement preserves prior state ACL'
            Assert-Equal $SentinelAclBefore (Get-WindowsAclSddl -LiteralPath $SentinelPath) 'temporary-leaf replacement preserves external sentinel ACL'
        }
    } $definitions $statePath $sentinelPath $stateBefore $sentinelBefore $stateModeBefore $sentinelModeBefore $stateAclBefore $sentinelAclBefore
}

function Test-WindowsStateTemporaryLeafReplacementAttack {
    if (-not $IsWindows) {
        return
    }
    Test-StateTemporaryLeafReplacementAttackCore
}

function Test-StateTemporaryLeafReplacementFailsClosed {
    Test-WindowsStateTransactionStructure
    Test-WindowsStateReplacesExistingFileWithHeldReader
    Test-WindowsStatePrimaryFailurePreservesErrorAndCleansTemporary
    Test-StateTemporaryLeafReplacementAttackCore
}

function Test-StateParentSwapPublishesOnlyToAuthenticatedParent {
    $testRoot = Join-Path $fixtureRoot 'state-parent-swap'
    $stateParent = Join-Path $testRoot 'state-parent'
    $authenticatedParent = Join-Path $testRoot 'authenticated-parent'
    $replacementParent = Join-Path $testRoot 'replacement-parent'
    $statePath = Join-Path $stateParent 'speckit-last-worktree.json'
    $sentinelPath = Join-Path $testRoot 'external-sentinel'
    [System.IO.Directory]::CreateDirectory($stateParent) | Out-Null
    [System.IO.File]::WriteAllText($statePath, 'trusted previous state', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($sentinelPath, 'attacker-controlled sentinel', [System.Text.UTF8Encoding]::new($false))
    if (-not $IsWindows) {
        [System.IO.File]::SetUnixFileMode($sentinelPath, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::GroupRead)
    }
    $sentinelBefore = [System.IO.File]::ReadAllBytes($sentinelPath)
    $sentinelModeBefore = if ($IsWindows) { $null } else { [System.IO.File]::GetUnixFileMode($sentinelPath) }
    $sentinelAclBefore = Get-WindowsAclSddl -LiteralPath $sentinelPath
    $definitions = Get-StateWriterDefinitions

    & {
        param($Definitions, $StateParent, $AuthenticatedParent, $ReplacementParent, $StatePath, $SentinelPath, $SentinelBefore, $SentinelModeBefore, $SentinelAclBefore)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }
        $script:stateFile = $StatePath
        $script:repoRoot = Split-Path $StateParent -Parent
        Initialize-SafeStateNativeApi
        $windowsTransaction = if ($IsWindows) {
            [Speckit.SafeWindowsStateTransaction]::new($StateParent)
        } else {
            $null
        }
        $script:ParentSwapCompleted = $false
        $swapParent = {
            param($TemporaryPath)
            [System.IO.Directory]::Move($StateParent, $AuthenticatedParent)
            if ($IsWindows) {
                [System.IO.Directory]::CreateDirectory($ReplacementParent) | Out-Null
                New-Item -ItemType HardLink -Path (Join-Path $ReplacementParent 'speckit-last-worktree.json') -Target $SentinelPath | Out-Null
                New-Item -ItemType HardLink -Path (Join-Path $ReplacementParent ([System.IO.Path]::GetFileName($TemporaryPath))) -Target $SentinelPath | Out-Null
                New-Item -ItemType Junction -Path $StateParent -Target $ReplacementParent | Out-Null
            } else {
                [System.IO.Directory]::CreateDirectory($StateParent) | Out-Null
                New-Item -ItemType HardLink -Path $StatePath -Target $SentinelPath | Out-Null
                New-Item -ItemType HardLink -Path (Join-Path $StateParent ([System.IO.Path]::GetFileName($TemporaryPath))) -Target $SentinelPath | Out-Null
            }
            $script:ParentSwapCompleted = $true
        }

        $publicationError = $null
        try {
            Write-LastWorktreeState -BranchName '052-parent-swap' -WorktreePath '/tmp/worktree' -BaseBranch 'main' -BeforePublish $swapParent -WindowsTransaction $windowsTransaction
        } catch {
            $publicationError = $_.Exception
        } finally {
            if ($null -ne $windowsTransaction) {
                try {
                    $windowsTransaction.Dispose()
                } catch {
                    if ($null -eq $publicationError) {
                        throw
                    }
                }
            }
        }
        Assert-True $script:ParentSwapCompleted 'parent swap race hook completed'

        $publishedStatePath = Join-Path $AuthenticatedParent 'speckit-last-worktree.json'
        if ($null -ne $publicationError) {
            throw "assertion failed: parent swap publication through authenticated parent succeeds: $($publicationError.Message)"
        }
        $publishedState = [System.IO.File]::ReadAllText($publishedStatePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
        Assert-Equal '052-parent-swap' $publishedState.BRANCH_NAME 'parent swap publishes trusted JSON to authenticated parent'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $AuthenticatedParent -Filter '.speckit-last-worktree.json.tmp.*' -Force).Count 'parent swap leaves no temporary in authenticated parent'
        Assert-True ([System.Linq.Enumerable]::SequenceEqual[byte]($SentinelBefore, [System.IO.File]::ReadAllBytes($StatePath))) 'parent swap leaves replacement-parent state bytes unchanged'
        Assert-True ([System.Linq.Enumerable]::SequenceEqual[byte]($SentinelBefore, [System.IO.File]::ReadAllBytes($SentinelPath))) 'parent swap preserves external sentinel bytes'
        if (-not $IsWindows) {
            Assert-Equal $SentinelModeBefore ([System.IO.File]::GetUnixFileMode($StatePath)) 'parent swap leaves replacement-parent state mode unchanged'
            Assert-Equal $SentinelModeBefore ([System.IO.File]::GetUnixFileMode($SentinelPath)) 'parent swap preserves external sentinel mode'
        } else {
            Assert-Equal $SentinelAclBefore (Get-WindowsAclSddl -LiteralPath $StatePath) 'parent junction leaves replacement-parent state ACL unchanged'
            Assert-Equal $SentinelAclBefore (Get-WindowsAclSddl -LiteralPath $SentinelPath) 'parent junction preserves external sentinel ACL'
        }
    } $definitions $stateParent $authenticatedParent $replacementParent $statePath $sentinelPath $sentinelBefore $sentinelModeBefore $sentinelAclBefore
}

function Test-WindowsStateAuthenticatedParentSwap {
    if (-not $IsWindows) {
        return
    }
    Test-StateParentSwapPublishesOnlyToAuthenticatedParent
}

function Test-PrunableWorktreeRecordsAreFinalizedBeforeLookup {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production lookup parse errors'
    $functionNames = @('ConvertFrom-GitCQuotedPath', 'Find-WorktreePathForBranch')
    $functionAsts = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -ccontains $node.Name
    }, $true))
    Assert-Equal 2 $functionAsts.Count 'production lookup helper count'
    $head = '1' * 40
    $branch = 'feature/031-prunable'
    $stalePath = Join-Path $fixtureRoot 'stale-prunable'

    & {
        param($Definitions, $Head, $Branch, $StalePath)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }

        $script:PorcelainMode = 'nul'
        function Invoke-GitWorktreePorcelain {
            param([switch]$NullDelimited)
            if ($script:PorcelainMode -eq 'nul') {
                $stdout = "worktree $StalePath$([char]0)HEAD $Head$([char]0)branch refs/heads/$Branch$([char]0)prunable gitdir file points to non-existent location$([char]0)$([char]0)"
                return [PSCustomObject]@{ ExitCode = 0; Stdout = $stdout; Stderr = '' }
            }
            if ($NullDelimited) {
                return [PSCustomObject]@{ ExitCode = 129; Stdout = ''; Stderr = 'unknown switch z' }
            }
            $stdout = "worktree $StalePath`nHEAD $Head`nbranch refs/heads/$Branch`nprunable gitdir file points to non-existent location`n`n"
            return [PSCustomObject]@{ ExitCode = 0; Stdout = $stdout; Stderr = '' }
        }

        Assert-Equal $null (Find-WorktreePathForBranch -BranchName $Branch) 'NUL prunable record lookup'
        $script:PorcelainMode = 'line'
        Assert-Equal $null (Find-WorktreePathForBranch -BranchName $Branch) 'line prunable record lookup'
    } $functionAsts $head $branch $stalePath
}

function Test-WorktreeLookupThrowsWhenBothPorcelainAttemptsFail {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production lookup parse errors'
    $functionNames = @('ConvertFrom-GitCQuotedPath', 'Find-WorktreePathForBranch')
    $functionAsts = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -ccontains $node.Name
    }, $true))
    Assert-Equal 2 $functionAsts.Count 'production lookup helper count'

    & {
        param($Definitions)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }

        $script:PorcelainCalls = 0
        function Invoke-GitWorktreePorcelain {
            param([switch]$NullDelimited)
            $script:PorcelainCalls++
            if ($NullDelimited) {
                return [PSCustomObject]@{ ExitCode = 129; Stdout = ''; Stderr = 'unknown switch z' }
            }
            return [PSCustomObject]@{ ExitCode = 128; Stdout = ''; Stderr = 'fallback porcelain failed' }
        }

        $thrown = $null
        try {
            Find-WorktreePathForBranch -BranchName 'feature/041-command-failure' | Out-Null
        } catch {
            $thrown = $_.Exception
        }

        Assert-Equal 2 $script:PorcelainCalls 'failed porcelain attempt count'
        Assert-True ($null -ne $thrown) 'both failed porcelain attempts throw instead of returning null'
    } $functionAsts
}

function Test-WorktreeLookupReturnsNullForSuccessfulNoMatch {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production lookup parse errors'
    $functionNames = @('ConvertFrom-GitCQuotedPath', 'Find-WorktreePathForBranch')
    $functionAsts = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -ccontains $node.Name
    }, $true))
    Assert-Equal 2 $functionAsts.Count 'production lookup helper count'
    $head = '2' * 40

    & {
        param($Definitions, $Head)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }

        $script:PorcelainCalls = 0
        function Invoke-GitWorktreePorcelain {
            param([switch]$NullDelimited)
            $script:PorcelainCalls++
            Assert-True $NullDelimited 'successful no-match uses NUL porcelain'
            $stdout = "worktree /tmp/unrelated$([char]0)HEAD $Head$([char]0)branch refs/heads/feature/042-unrelated$([char]0)$([char]0)"
            return [PSCustomObject]@{ ExitCode = 0; Stdout = $stdout; Stderr = '' }
        }

        Assert-Equal $null (Find-WorktreePathForBranch -BranchName 'feature/042-missing') 'successful no-match lookup'
        Assert-Equal 1 $script:PorcelainCalls 'successful no-match porcelain attempt count'
    } $functionAsts $head
}

function Test-AmbiguousLinePorcelainThrows {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production lookup parse errors'
    $functionNames = @('ConvertFrom-GitCQuotedPath', 'Find-WorktreePathForBranch')
    $functionAsts = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -ccontains $node.Name
    }, $true))
    Assert-Equal 2 $functionAsts.Count 'production lookup helper count'
    $firstHead = '3' * 40
    $secondHead = '4' * 40
    $branch = 'feature/043-ambiguous-head'
    $worktreePath = Join-Path $fixtureRoot 'ambiguous-head-worktree'

    & {
        param($Definitions, $FirstHead, $SecondHead, $Branch, $WorktreePath)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }

        function Invoke-GitWorktreePorcelain {
            param([switch]$NullDelimited)
            if ($NullDelimited) {
                return [PSCustomObject]@{ ExitCode = 129; Stdout = ''; Stderr = 'unknown switch z' }
            }
            $stdout = "worktree $WorktreePath`nHEAD $FirstHead`nHEAD $SecondHead`nbranch refs/heads/$Branch`n`n"
            return [PSCustomObject]@{ ExitCode = 0; Stdout = $stdout; Stderr = '' }
        }

        $thrown = $null
        try {
            Find-WorktreePathForBranch -BranchName $Branch | Out-Null
        } catch {
            $thrown = $_.Exception
        }

        Assert-True ($null -ne $thrown) 'ambiguous line porcelain with two HEAD fields throws'
    } $functionAsts $firstHead $secondHead $branch $worktreePath
}

function Test-WorktreeCandidateRequiresLiveCorroboration {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production candidate validation parse errors'
    $functionNames = @('ConvertFrom-GitCQuotedPath', 'Assert-WorktreeCandidateValid', 'Find-WorktreePathForBranch')
    $functionAsts = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -ccontains $node.Name
    }, $true))
    Assert-Equal 3 $functionAsts.Count 'production candidate validation helper count'

    $repository = Initialize-Fixture -Name 'candidate-corroboration' -Config "checkout_mode: worktree`nbase_branch: main"
    $configuredRoot = $fixtureRoot
    $head = Invoke-GitText -Repository $repository -Arguments @('rev-parse', 'HEAD')

    & {
        param($Definitions, $Repository, $ConfiguredRoot, $Head)
        foreach ($definition in $Definitions) {
            Invoke-Expression $definition.Extent.Text
        }

        $script:repoRoot = $Repository
        $script:worktreeRoot = $ConfiguredRoot
        $script:commonDir = [System.IO.Path]::GetFullPath((Join-Path $Repository '.git'))
        function Invoke-GitWorktreePorcelain {
            param([switch]$NullDelimited)
            Assert-True $NullDelimited 'forged candidate test uses NUL porcelain'
            $stdout = "worktree $Repository$([char]0)HEAD $Head$([char]0)branch refs/heads/main$([char]0)$([char]0)"
            return [PSCustomObject]@{ ExitCode = 0; Stdout = $stdout; Stderr = '' }
        }

        $thrown = $null
        try {
            Find-WorktreePathForBranch -BranchName 'main' | Out-Null
        } catch {
            $thrown = $_.Exception
        }

        Assert-True ($null -ne $thrown) 'forged main-checkout candidate is rejected by live corroboration'
    } $functionAsts $repository $configuredRoot $head
}

function Test-WildcardBearingPathsRemainLiteral {
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceFeatureScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'production path helper parse errors'
    $highestNumberAst = $scriptAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-HighestNumberFromSpecs'
    }, $true)
    Assert-True ($null -ne $highestNumberAst) 'production specs numbering helper exists'

    $failures = [System.Collections.Generic.List[string]]::new()
    try {
        & {
            param($Definition, $SpecsDir)
            Invoke-Expression $Definition.Extent.Text
            $script:SpecsTestWasLiteral = $false
            $script:SpecsEnumerationWasLiteral = $false
            function Test-Path {
                param([string]$Path, [string]$LiteralPath)
                $script:SpecsTestWasLiteral = $PSBoundParameters.ContainsKey('LiteralPath')
                return $true
            }
            function Get-ChildItem {
                param([string]$Path, [string]$LiteralPath, [switch]$Directory)
                $script:SpecsEnumerationWasLiteral = $PSBoundParameters.ContainsKey('LiteralPath')
                return @()
            }

            Assert-Equal 0 (Get-HighestNumberFromSpecs -SpecsDir $SpecsDir) 'wildcard-bearing specs path ignores decoy root1'
            Assert-True ($script:SpecsTestWasLiteral -and $script:SpecsEnumerationWasLiteral) 'specs lookup uses literal Test-Path and Get-ChildItem parameters'
        } $highestNumberAst (Join-Path $fixtureRoot 'number-root[1]/specs')
    } catch {
        $failures.Add($_.Exception.Message)
    }

    $repository = Initialize-Fixture -Name 'literal-worktree-path' -Config "checkout_mode: worktree`nbase_branch: main"
    $branch = '044-literal-worktree-root'
    $literalWorktreeRoot = Join-Path $fixtureRoot 'worktree-root[1]'
    $literalWorktreePath = Join-Path $literalWorktreeRoot $branch
    $decoyWorktreePath = Join-Path (Join-Path $fixtureRoot 'worktree-root1') $branch
    [System.IO.Directory]::CreateDirectory($decoyWorktreePath) | Out-Null

    $result = Invoke-Feature -Repository $repository -Description 'ignored' -ExactBranch $branch -WorktreeRoot $literalWorktreeRoot
    try {
        Assert-Equal 0 $result.ExitCode 'wildcard-bearing worktree root ignores decoy root1'
        Assert-Equal $literalWorktreePath $result.Json.WORKTREE_PATH 'wildcard-bearing literal WORKTREE_PATH'
        Assert-Worktree -Repository $repository -ExpectedBranch $branch -ExpectedPath $literalWorktreePath
        Assert-True ([System.IO.Directory]::Exists($decoyWorktreePath)) 'decoy root1 directory remains untouched'
        Assert-True ((Get-RegisteredWorktreePaths -Repository $repository) -cnotcontains $decoyWorktreePath) 'decoy root1 directory is not registered'
    } catch {
        $failures.Add($_.Exception.Message)
    }

    if ($failures.Count -ne 0) {
        throw "assertion failed: wildcard-bearing paths must remain literal: $($failures -join '; ')"
    }
}

function Test-ConcurrentSequentialNumberReservations {
    $repository = Initialize-Fixture -Name 'concurrent-numbering' -Config "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../concurrent-numbering-worktrees`nbranch_prefix: feature/"
    Invoke-GitText -Repository $repository -Arguments @('branch', 'feature/001-existing') | Out-Null
    $shimDirectory = Join-Path $fixtureRoot 'concurrent-numbering-git-shim'
    Install-NumberReservationGitShim -Directory $shimDirectory | Out-Null
    $barrierDirectory = Join-Path $fixtureRoot 'concurrent-numbering-barrier'
    foreach ($leaf in @('arrivals', 'snapshots', 'gates')) {
        [System.IO.Directory]::CreateDirectory((Join-Path $barrierDirectory $leaf)) | Out-Null
    }
    $reservationLog = Join-Path $fixtureRoot 'concurrent-numbering-reservations.log'
    [System.IO.File]::WriteAllText($reservationLog, '')
    $creatorNames = @('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel')
    $gateStreams = @{}
    $bashRepositories = @{}
    $invocations = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.List[object]]::new()
    $realGit = (Get-Command git -ErrorAction Stop).Source

    try {
        for ($creatorIndex = 1; $creatorIndex -lt $creatorNames.Count; $creatorIndex += 2) {
            $creatorName = $creatorNames[$creatorIndex]
            $bashRepository = Join-Path $fixtureRoot "concurrent-numbering-bash-$creatorName"
            Invoke-GitText -Repository $repository -Arguments @('worktree', 'add', '--detach', $bashRepository, 'HEAD') | Out-Null
            $bashRepositories[$creatorName] = $bashRepository
        }
        for ($creatorIndex = 0; $creatorIndex -lt $creatorNames.Count; $creatorIndex++) {
            $creatorName = $creatorNames[$creatorIndex]
            $gatePath = Join-Path (Join-Path $barrierDirectory 'gates') $creatorName
            $gateStreams[$creatorName] = New-TestFifo -Path $gatePath
            $environment = @{
                PATH = "$shimDirectory$([System.IO.Path]::PathSeparator)$env:PATH"
                SPECKIT_TEST_REAL_GIT = $realGit
                SPECKIT_TEST_GIT_MODE = 'branch-snapshot-barrier'
                SPECKIT_TEST_BARRIER_DIR = $barrierDirectory
                SPECKIT_TEST_CREATOR_ID = $creatorName
                SPECKIT_TEST_RESERVATION_LOG = $reservationLog
            }
            $invocation = if ($creatorIndex % 2 -eq 0) {
                Start-FeatureProcess -Repository $repository -Description "Concurrent $creatorName" -Environment $environment
            } else {
                $environment['SPECKIT_GIT_CHECKOUT_MODE'] = 'branch'
                Start-BashFeatureProcess -Repository $bashRepositories[$creatorName] -Description "Concurrent $creatorName" -Environment $environment
            }
            $invocation | Add-Member -NotePropertyName CreatorName -NotePropertyValue $creatorName
            $invocation | Add-Member -NotePropertyName CreatorShell -NotePropertyValue $(if ($creatorIndex % 2 -eq 0) { 'PowerShell' } else { 'Bash' })
            $invocations.Add($invocation)
        }

        try {
            Wait-ForBarrierFiles -Directory (Join-Path $barrierDirectory 'arrivals') -ExpectedCount $creatorNames.Count
        } catch {
            $processStates = foreach ($invocation in $invocations) {
                if ($invocation.Process.HasExited) {
                    "$($invocation.CreatorShell) $($invocation.CreatorName) exited $($invocation.Process.ExitCode): $($invocation.Stderr.GetAwaiter().GetResult().Trim())"
                } else {
                    "$($invocation.CreatorShell) $($invocation.CreatorName) is waiting"
                }
            }
            throw "$($_.Exception.Message); $($processStates -join '; ')"
        }
        foreach ($creatorName in $creatorNames) {
            Open-TestFifoGate -Stream $gateStreams[$creatorName]
        }
        foreach ($invocation in $invocations) {
            $results.Add((Complete-FeatureProcess -Invocation $invocation))
        }

        $failed = @($results | Where-Object { $_.ExitCode -ne 0 })
        $failureText = ($failed | ForEach-Object { $_.Stderr.Trim() }) -join '; '
        Assert-Equal 0 $failed.Count "all concurrent PowerShell and Bash creators succeed: $failureText"
        $numbers = @($results | ForEach-Object { $_.Json.FEATURE_NUM } | Sort-Object)
        Assert-Equal '002,003,004,005,006,007,008,009' ($numbers -join ',') 'concurrent feature numbers'
        Assert-Equal 8 @($results.Json.BRANCH_NAME | Sort-Object -Unique).Count 'concurrent branches are distinct'
        $powerShellResults = @($results | Where-Object { $null -ne $_.Json.PSObject.Properties['WORKTREE_PATH'] })
        Assert-Equal 4 @($powerShellResults.Json.WORKTREE_PATH | Sort-Object -Unique).Count 'concurrent PowerShell worktree paths are distinct'
        for ($creatorIndex = 0; $creatorIndex -lt $results.Count; $creatorIndex++) {
            $result = $results[$creatorIndex]
            $creatorName = $creatorNames[$creatorIndex]
            if ($creatorIndex % 2 -eq 0) {
                Assert-Worktree -Repository $repository -ExpectedBranch $result.Json.BRANCH_NAME -ExpectedPath $result.Json.WORKTREE_PATH
            } else {
                Assert-Equal $result.Json.BRANCH_NAME (Invoke-GitText -Repository $bashRepositories[$creatorName] -Arguments @('branch', '--show-current')) "concurrent Bash branch checkout for $creatorName"
            }
        }
        Assert-Equal '' (Get-NumberReservationRefs -Repository $repository) 'reservation refs after concurrent success'
        $scopeHash = Get-GitObjectHash -Repository $repository -Value 'feature/'
        $reservationLogText = [System.IO.File]::ReadAllText($reservationLog)
        Assert-Contains $reservationLogText "refs/speckit/number-reservations/v1/$scopeHash/002" 'concurrent reservation uses Bash-compatible scope hash and namespace'
        $ownerOids = @($reservationLogText -split '\r?\n' | ForEach-Object {
            if ($_ -match '^update-ref refs/speckit/number-reservations/v1/\S+ (?<oid>[0-9a-f]{40,64})(?: |$)') {
                $matches['oid']
            }
        } | Sort-Object -Unique)
        Assert-Equal 8 $ownerOids.Count 'eight same-HEAD PowerShell and Bash creators use distinct reservation owner OIDs'
        foreach ($ownerOid in $ownerOids) {
            Assert-Equal 'blob' (Invoke-GitText -Repository $repository -Arguments @('cat-file', '-t', $ownerOid)) "reservation owner object $ownerOid is a blob"
        }
    } finally {
        Stop-PendingFeatureProcesses -Invocations $invocations
        foreach ($stream in $gateStreams.Values) {
            $stream.Dispose()
        }
    }
}

function Test-ReleasedReservationStaleScanRetry {
    $repository = Initialize-Fixture -Name 'released-reservation-interleaving' -Config "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../released-reservation-worktrees`nbranch_prefix: feature/"
    Invoke-GitText -Repository $repository -Arguments @('branch', 'feature/001-existing') | Out-Null
    $shimDirectory = Join-Path $fixtureRoot 'released-reservation-git-shim'
    Install-NumberReservationGitShim -Directory $shimDirectory | Out-Null
    $barrierDirectory = Join-Path $fixtureRoot 'released-reservation-barrier'
    foreach ($leaf in @('arrivals', 'snapshots', 'gates', 'branch-gate-ready', 'release-gate-ready')) {
        [System.IO.Directory]::CreateDirectory((Join-Path $barrierDirectory $leaf)) | Out-Null
    }
    $branchGateReadyDirectory = Join-Path $barrierDirectory 'branch-gate-ready'
    $releaseGateReadyDirectory = Join-Path $barrierDirectory 'release-gate-ready'
    $publisherGate = New-TestFifo -Path (Join-Path $barrierDirectory 'gates/publisher')
    $delayedGate = New-TestFifo -Path (Join-Path $barrierDirectory 'gates/delayed')
    $releaseGatePath = Join-Path $barrierDirectory 'publisher-release-gate'
    $releaseGate = New-TestFifo -Path $releaseGatePath
    $releaseMarker = Join-Path $barrierDirectory 'publisher-released-002'
    $realGit = (Get-Command git -ErrorAction Stop).Source
    $baseEnvironment = @{
        PATH = "$shimDirectory$([System.IO.Path]::PathSeparator)$env:PATH"
        SPECKIT_TEST_REAL_GIT = $realGit
        SPECKIT_TEST_GIT_MODE = 'released-reservation-interleaving'
        SPECKIT_TEST_BARRIER_DIR = $barrierDirectory
        SPECKIT_TEST_BRANCH_GATE_READY_DIR = $branchGateReadyDirectory
        SPECKIT_TEST_RELEASE_GATE = $releaseGatePath
        SPECKIT_TEST_RELEASE_GATE_READY_DIR = $releaseGateReadyDirectory
        SPECKIT_TEST_RELEASE_MARKER = $releaseMarker
    }
    $invocations = [System.Collections.Generic.List[object]]::new()

    try {
        $publisherEnvironment = $baseEnvironment.Clone()
        $publisherEnvironment['SPECKIT_TEST_CREATOR_ID'] = 'publisher'
        $publisherEnvironment['SPECKIT_TEST_CREATOR_ROLE'] = 'publisher'
        $delayedEnvironment = $baseEnvironment.Clone()
        $delayedEnvironment['SPECKIT_TEST_CREATOR_ID'] = 'delayed'
        $delayedEnvironment['SPECKIT_TEST_CREATOR_ROLE'] = 'delayed'
        $publisher = Start-FeatureProcess -Repository $repository -Description 'Published first' -Environment $publisherEnvironment
        $delayed = Start-FeatureProcess -Repository $repository -Description 'Delayed claim' -Environment $delayedEnvironment
        $invocations.Add($publisher)
        $invocations.Add($delayed)

        Wait-ForBarrierFiles -Directory (Join-Path $barrierDirectory 'arrivals') -ExpectedCount 2
        Wait-ForBarrierFiles -Directory $branchGateReadyDirectory -ExpectedCount 2
        $releaseGate.Dispose()
        Open-TestFifoGate -Stream $publisherGate
        Open-TestFifoGate -Stream $delayedGate
        Wait-ForBarrierFiles -Directory $releaseGateReadyDirectory -ExpectedCount 1
        try {
            $publisherResult = Complete-FeatureProcess -Invocation $publisher
        } catch {
            throw "publisher creator did not complete: $($_.Exception.Message)"
        }
        try {
            $delayedResult = Complete-FeatureProcess -Invocation $delayed
        } catch {
            throw "delayed creator did not complete: $($_.Exception.Message)"
        }

        Assert-Equal 0 $publisherResult.ExitCode "publisher creator succeeds: $($publisherResult.Stderr)"
        Assert-Equal 0 $delayedResult.ExitCode "delayed creator succeeds: $($delayedResult.Stderr)"
        Assert-Equal '002' $publisherResult.Json.FEATURE_NUM 'publisher feature number'
        Assert-Equal '003' $delayedResult.Json.FEATURE_NUM 'delayed stale claim retry feature number'
        Assert-True ([System.IO.File]::Exists($releaseMarker)) 'publisher release marker exists'
        Assert-Worktree -Repository $repository -ExpectedBranch $publisherResult.Json.BRANCH_NAME -ExpectedPath $publisherResult.Json.WORKTREE_PATH
        Assert-Worktree -Repository $repository -ExpectedBranch $delayedResult.Json.BRANCH_NAME -ExpectedPath $delayedResult.Json.WORKTREE_PATH
        Assert-Equal '' (Get-NumberReservationRefs -Repository $repository) 'reservation refs after stale successful claim retry'
    } finally {
        Stop-PendingFeatureProcesses -Invocations $invocations
        $publisherGate.Dispose()
        $delayedGate.Dispose()
        $releaseGate.Dispose()
    }
}

function Test-ReservationSuccessAndFailureCleanup {
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../reservation-cleanup-worktrees`nbranch_prefix: team/"
    $repository = Initialize-Fixture -Name 'reservation-cleanup' -Config $config
    Invoke-GitText -Repository $repository -Arguments @('branch', 'team/001-existing') | Out-Null

    $success = Invoke-Feature -Repository $repository -Description 'Successful reservation cleanup'
    Assert-Equal 0 $success.ExitCode 'successful reservation cleanup exit code'
    Assert-Equal 'team/002-successful-reservation-cleanup' $success.Json.BRANCH_NAME 'successful reserved branch'
    Assert-Worktree -Repository $repository -ExpectedBranch $success.Json.BRANCH_NAME -ExpectedPath $success.Json.WORKTREE_PATH
    Assert-Equal '' (Get-NumberReservationRefs -Repository $repository) 'reservation refs after success'

    $configFile = Join-Path $repository '.specify/extensions/git/git-config.yml'
    [System.IO.File]::WriteAllText($configFile, $config.Replace('base_branch: main', 'base_branch: missing-base'), [System.Text.UTF8Encoding]::new($false))
    $failure = Invoke-Feature -Repository $repository -Description 'Failed reservation cleanup'
    Assert-True ($failure.ExitCode -ne 0) 'missing-base creator fails'
    Assert-Contains $failure.Stderr "Base branch 'missing-base' does not exist" 'missing-base failure is exercised'
    Assert-Equal '' (Get-NumberReservationRefs -Repository $repository) 'reservation refs after failed creator'
    Assert-Equal '' (Invoke-GitText -Repository $repository -Arguments @('branch', '--list', 'team/003-*')) 'failed creator leaves no feature branch'
}

function Test-ReservationUpdateRefFailures {
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../reservation-update-failure-worktrees`nbranch_prefix: feature/"
    $repository = Initialize-Fixture -Name 'reservation-update-failure' -Config $config
    Invoke-GitText -Repository $repository -Arguments @('branch', 'feature/001-existing') | Out-Null
    $shimDirectory = Join-Path $fixtureRoot 'reservation-update-failure-git-shim'
    Install-NumberReservationGitShim -Directory $shimDirectory | Out-Null
    $reservationLog = Join-Path $fixtureRoot 'reservation-update-failure.log'
    [System.IO.File]::WriteAllText($reservationLog, '')
    $shimEnvironment = @{
        PATH = "$shimDirectory$([System.IO.Path]::PathSeparator)$env:PATH"
        SPECKIT_TEST_REAL_GIT = (Get-Command git -ErrorAction Stop).Source
        SPECKIT_TEST_GIT_MODE = 'fail-reservation-create'
        SPECKIT_TEST_RESERVATION_LOG = $reservationLog
    }

    $failure = Invoke-Feature -Repository $repository -Description 'Fatal update ref failure' -Environment $shimEnvironment
    Assert-True ($failure.ExitCode -ne 0) 'unrelated update-ref failure is fatal'
    Assert-Contains $failure.Stderr 'Failed to reserve sequential feature number 002' 'unrelated update-ref failure diagnostic'
    Assert-Contains $failure.Stderr 'forced unrelated' 'unrelated update-ref preserves first Git diagnostic fragment'
    Assert-Contains $failure.Stderr 'update-ref failure' 'unrelated update-ref preserves second Git diagnostic fragment'
    Assert-True ((Get-Item -LiteralPath $reservationLog).Length -gt 0) 'unrelated update-ref failure shim is exercised'
    Assert-Equal '' (Get-NumberReservationRefs -Repository $repository) 'reservation refs after unrelated update-ref failure'

    $releaseRepository = Initialize-Fixture -Name 'reservation-release-failure' -Config "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../reservation-release-failure-worktrees`nbranch_prefix: release/"
    $deleteFailureMarker = Join-Path $fixtureRoot 'reservation-delete-failed-once'
    $releaseEnvironment = $shimEnvironment.Clone()
    $releaseEnvironment['SPECKIT_TEST_GIT_MODE'] = 'fail-reservation-delete-once'
    $releaseEnvironment['SPECKIT_TEST_DELETE_FAILURE_MARKER'] = $deleteFailureMarker
    $releaseFailure = Invoke-Feature -Repository $releaseRepository -Description 'Fatal release failure' -Environment $releaseEnvironment
    Assert-True ($releaseFailure.ExitCode -ne 0) 'explicit reservation release failure is fatal'
    Assert-Contains $releaseFailure.Stderr 'Failed to release owned feature number reservation' 'explicit release failure diagnostic'
    Assert-Contains $releaseFailure.Stderr 'forced reservation delete failure' 'explicit release preserves Git diagnostic'
    Assert-True ([System.IO.File]::Exists($deleteFailureMarker)) 'explicit release failure shim is exercised'
    Assert-Equal '' (Get-NumberReservationRefs -Repository $releaseRepository) 'emergency cleanup retries failed explicit release with expected OID'

    $replacementRepository = Initialize-Fixture -Name 'reservation-owner-replacement' -Config "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../reservation-owner-replacement-worktrees`nbranch_prefix: replacement/"
    $replacementMarker = Join-Path $fixtureRoot 'reservation-owner-replaced'
    $otherOid = Invoke-GitText -Repository $replacementRepository -Arguments @('rev-parse', 'HEAD^{tree}')
    $replacementEnvironment = $shimEnvironment.Clone()
    $replacementEnvironment['SPECKIT_TEST_GIT_MODE'] = 'replace-reservation-owner'
    $replacementEnvironment['SPECKIT_TEST_OWNER_REPLACEMENT_MARKER'] = $replacementMarker
    $replacementEnvironment['SPECKIT_TEST_OTHER_OID'] = $otherOid
    $replacementFailure = Invoke-Feature -Repository $replacementRepository -Description 'Preserve replacement owner' -Environment $replacementEnvironment
    Assert-True ($replacementFailure.ExitCode -ne 0) 'ownership replacement makes explicit release fatal'
    Assert-Contains $replacementFailure.Stderr 'Failed to release owned feature number reservation' 'ownership replacement release diagnostic'
    Assert-True ([System.IO.File]::Exists($replacementMarker)) 'ownership replacement shim is exercised'
    $replacementScopeHash = Get-GitObjectHash -Repository $replacementRepository -Value 'replacement/'
    $replacementRef = "refs/speckit/number-reservations/v1/$replacementScopeHash/001"
    Assert-Equal $replacementRef (Get-NumberReservationRefs -Repository $replacementRepository) 'emergency cleanup preserves another owner reservation ref'
    Assert-Equal $otherOid (Invoke-GitText -Repository $replacementRepository -Arguments @('rev-parse', $replacementRef)) 'emergency cleanup preserves another owner OID'
}

function Test-BranchModeReservationCleanup {
    $repository = Initialize-Fixture -Name 'reservation-branch-mode' -Config "checkout_mode: branch`nbase_branch: main`nbranch_prefix: branch-mode/"
    Invoke-GitText -Repository $repository -Arguments @('branch', 'branch-mode/001-existing') | Out-Null

    $result = Invoke-Feature -Repository $repository -Description 'Branch checkout cleanup'
    Assert-Equal 0 $result.ExitCode 'branch-mode reservation cleanup exit code'
    Assert-Equal 'branch-mode/002-branch-checkout-cleanup' $result.Json.BRANCH_NAME 'branch-mode reserved branch'
    Assert-Equal $result.Json.BRANCH_NAME (Invoke-GitText -Repository $repository -Arguments @('branch', '--show-current')) 'branch-mode checkout'
    Assert-Equal '' (Get-NumberReservationRefs -Repository $repository) 'reservation refs after checkout -b success'
}

function Test-OrphanReservationGapAndScopeIsolation {
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../orphan-reservation-worktrees`nbranch_prefix: feature/"
    $repository = Initialize-Fixture -Name 'orphan-reservation' -Config $config
    Invoke-GitText -Repository $repository -Arguments @('branch', 'feature/001-existing') | Out-Null
    $scopeHash = Get-GitObjectHash -Repository $repository -Value 'feature/'
    $headOid = Invoke-GitText -Repository $repository -Arguments @('rev-parse', 'HEAD')
    $orphanRef = "refs/speckit/number-reservations/v1/$scopeHash/002"
    Invoke-GitText -Repository $repository -Arguments @('update-ref', $orphanRef, $headOid, '') | Out-Null

    $sameScope = Invoke-Feature -Repository $repository -Description 'Skip orphan reservation'
    Assert-Equal 0 $sameScope.ExitCode 'orphan-gap creator exit code'
    Assert-Equal 'feature/003-skip-orphan-reservation' $sameScope.Json.BRANCH_NAME 'orphan-gap branch'
    Assert-Worktree -Repository $repository -ExpectedBranch $sameScope.Json.BRANCH_NAME -ExpectedPath $sameScope.Json.WORKTREE_PATH

    $configFile = Join-Path $repository '.specify/extensions/git/git-config.yml'
    [System.IO.File]::WriteAllText($configFile, $config.Replace('branch_prefix: feature/', 'branch_prefix: other/'), [System.Text.UTF8Encoding]::new($false))
    $otherScope = Invoke-Feature -Repository $repository -Description 'Independent reservation scope'
    Assert-Equal 0 $otherScope.ExitCode 'independent-scope creator exit code'
    Assert-Equal 'other/001-independent-reservation-scope' $otherScope.Json.BRANCH_NAME 'independent-scope branch'
    Assert-Worktree -Repository $repository -ExpectedBranch $otherScope.Json.BRANCH_NAME -ExpectedPath $otherScope.Json.WORKTREE_PATH
    Assert-Equal $orphanRef (Get-NumberReservationRefs -Repository $repository) 'unknown Bash-compatible orphan reservation is preserved'
}

function Test-NonReservingNumberingPaths {
    $shimDirectory = Join-Path $fixtureRoot 'non-reserving-git-shim'
    Install-NumberReservationGitShim -Directory $shimDirectory | Out-Null
    $reservationLog = Join-Path $fixtureRoot 'non-reserving-update-ref.log'
    [System.IO.File]::WriteAllText($reservationLog, '')
    $environment = @{
        PATH = "$shimDirectory$([System.IO.Path]::PathSeparator)$env:PATH"
        SPECKIT_TEST_REAL_GIT = (Get-Command git -ErrorAction Stop).Source
        SPECKIT_TEST_RESERVATION_LOG = $reservationLog
    }
    $config = "checkout_mode: worktree`nbase_branch: main`nworktree_root: ../non-reserving-worktrees"

    $exactRepository = Initialize-Fixture -Name 'non-reserving-exact' -Config $config
    $exact = Invoke-Feature -Repository $exactRepository -Description 'ignored' -ExactBranch 'manual/041-exact-name' -Environment $environment
    Assert-Equal 0 $exact.ExitCode 'exact branch bypass exit code'
    Assert-Equal 'manual/041-exact-name' $exact.Json.BRANCH_NAME 'exact branch bypass'

    $explicitRepository = Initialize-Fixture -Name 'non-reserving-explicit' -Config $config
    $explicit = Invoke-Feature -Repository $explicitRepository -Description 'Explicit number' -Options @('-Number', '42') -Environment $environment
    Assert-Equal 0 $explicit.ExitCode 'explicit number bypass exit code'
    Assert-Equal '042-explicit-number' $explicit.Json.BRANCH_NAME 'explicit number bypass'

    $timestampRepository = Initialize-Fixture -Name 'non-reserving-timestamp' -Config $config
    $timestamp = Invoke-Feature -Repository $timestampRepository -Description 'Timestamp number' -Options @('-Timestamp') -Environment $environment
    Assert-Equal 0 $timestamp.ExitCode 'timestamp bypass exit code'
    Assert-True ($timestamp.Json.FEATURE_NUM -match '^\d{8}-\d{6}$') 'timestamp bypass produces a timestamp'

    $dryRunRepository = Initialize-Fixture -Name 'non-reserving-dry-run' -Config $config
    $dryRun = Invoke-Feature -Repository $dryRunRepository -Description 'Dry run number' -Options @('-DryRun') -Environment $environment
    Assert-Equal 0 $dryRun.ExitCode 'dry-run bypass exit code'
    Assert-Equal '001-dry-run-number' $dryRun.Json.BRANCH_NAME 'dry-run bypass'

    $noGitRepository = Join-Path $fixtureRoot 'non-reserving-no-git'
    $noGitScriptDirectory = Join-Path $noGitRepository '.specify/extensions/git/scripts/powershell'
    [System.IO.Directory]::CreateDirectory($noGitScriptDirectory) | Out-Null
    Copy-Item -LiteralPath $sourceFeatureScript -Destination $noGitScriptDirectory
    Copy-Item -LiteralPath $sourceCommonScript -Destination $noGitScriptDirectory
    [System.IO.File]::WriteAllText(
        (Join-Path $noGitRepository '.specify/extensions/git/git-config.yml'),
        "checkout_mode: branch`nbranch_numbering: sequential`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $noGit = Invoke-Feature -Repository $noGitRepository -Description 'No Git number' -Environment $environment
    Assert-Equal 0 $noGit.ExitCode 'no-Git bypass exit code'
    Assert-Equal $false $noGit.Json.HAS_GIT 'no-Git bypass'

    Assert-Equal 0 (Get-Item -LiteralPath $reservationLog).Length 'exact, explicit, timestamp, dry-run, and no-Git paths never touch reservation refs'
}

function Test-LegacyDashPrefixedDescriptionParsing {
    $repository = Initialize-Fixture -Name 'legacy-dash-description' -Config "checkout_mode: worktree`nbase_branch: main"
    $result = Invoke-Feature -Repository $repository -Description '-dash-prefixed legacy description' -Options @('-DryRun', '-Number', '7', '-FeatureDescription')

    Assert-Equal 0 $result.ExitCode 'legacy dash-prefixed description exit code'
    Assert-Equal '007-dash-prefixed-legacy-description' $result.Json.BRANCH_NAME 'legacy dash-prefixed description BRANCH_NAME'
    Assert-Equal '007' $result.Json.FEATURE_NUM 'legacy dash-prefixed description FEATURE_NUM'
    Assert-Equal $true $result.Json.DRY_RUN 'legacy dash-prefixed description DRY_RUN'
}

$defaultScenarios = [ordered]@{
    'default sequential worktree and JSON fields' = ${function:Test-DefaultSequentialWorktree}
    'namespaced sequential numbering' = ${function:Test-NamespacedSequentialNumbering}
    'root numbering ignores namespaced refs' = ${function:Test-RootNumberingIgnoresNamespacedRefs}
    'repeated {number} rejection before mutation' = ${function:Test-RepeatedNumberRejectedBeforeMutation}
    'unsupported token rejection before mutation' = ${function:Test-UnsupportedTokenRejectedBeforeMutation}
    'negative -Number rejection before mutation' = ${function:Test-NegativeNumberRejectedBeforeMutation}
    'dry-run non-mutation' = ${function:Test-DryRunNonMutation}
    'empty-slug truncation refusal' = ${function:Test-TruncationRefusesEmptySlug}
    'allow-existing-branch special-path idempotency' = ${function:Test-AllowExistingBranchIdempotency}
    'Git C-quoted worktree path decoding' = ${function:Test-GitCQuotedPathDecoder}
    'reparse-point state rejection before mutation' = ${function:Test-StateReparsePointRejectedBeforeMutation}
    'malformed regular state atomic recovery' = ${function:Test-MalformedRegularStateIsAtomicallyReplaced}
    'state temporary-leaf replacement fails closed' = ${function:Test-StateTemporaryLeafReplacementFailsClosed}
    'state parent swap publishes only to authenticated parent' = ${function:Test-StateParentSwapPublishesOnlyToAuthenticatedParent}
    'prunable worktree records are finalized before lookup' = ${function:Test-PrunableWorktreeRecordsAreFinalizedBeforeLookup}
    'both failed porcelain attempts throw' = ${function:Test-WorktreeLookupThrowsWhenBothPorcelainAttemptsFail}
    'successful worktree no-match returns null' = ${function:Test-WorktreeLookupReturnsNullForSuccessfulNoMatch}
    'ambiguous line porcelain with two HEAD fields throws' = ${function:Test-AmbiguousLinePorcelainThrows}
    'matching worktree candidate requires live corroboration' = ${function:Test-WorktreeCandidateRequiresLiveCorroboration}
    'wildcard-bearing paths remain literal' = ${function:Test-WildcardBearingPathsRemainLiteral}
    'concurrent PowerShell and Bash sequential number reservations' = ${function:Test-ConcurrentSequentialNumberReservations}
    'released reservation stale-scan retry' = ${function:Test-ReleasedReservationStaleScanRetry}
    'reservation success and failure cleanup' = ${function:Test-ReservationSuccessAndFailureCleanup}
    'reservation update-ref failures' = ${function:Test-ReservationUpdateRefFailures}
    'branch-mode reservation cleanup' = ${function:Test-BranchModeReservationCleanup}
    'orphan reservation gap and scope isolation' = ${function:Test-OrphanReservationGapAndScopeIsolation}
    'non-reserving numbering paths' = ${function:Test-NonReservingNumberingPaths}
    'legacy dash-prefixed description parsing' = ${function:Test-LegacyDashPrefixedDescriptionParsing}
}

$windowsStateScenarios = [ordered]@{
    'Windows state transaction structural contract' = ${function:Test-WindowsStateTransactionStructure}
    'Windows state replaces existing file with held reader' = ${function:Test-WindowsStateReplacesExistingFileWithHeldReader}
    'Windows state primary failure preserves error and cleans temporary' = ${function:Test-WindowsStatePrimaryFailurePreservesErrorAndCleansTemporary}
    'Windows state temporary-leaf replacement attack fails closed' = ${function:Test-WindowsStateTemporaryLeafReplacementAttack}
    'Windows state publishes only to authenticated parent' = ${function:Test-WindowsStateAuthenticatedParentSwap}
}

$scenarios = if ($WindowsStateOnly) {
    $windowsStateScenarios
} else {
    $defaultScenarios
}

$failures = 0
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
try {
    foreach ($scenario in $scenarios.GetEnumerator()) {
        try {
            & $scenario.Value
            Write-Output "PASS: $($scenario.Key)"
        } catch {
            [Console]::Error.WriteLine("FAIL: $($scenario.Key): $($_.Exception.Message)")
            $failures++
        }
    }
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

if ($failures -ne 0) {
    [Console]::Error.WriteLine("RED: Speckit Git PowerShell behavior tests failed: $failures scenario(s)")
    exit 1
}

if ($WindowsStateOnly) {
    Write-Output "GREEN: Speckit Git PowerShell behavior tests passed ($($scenarios.Count) selected Windows state scenarios)"
} else {
    Write-Output "GREEN: Speckit Git PowerShell behavior tests passed ($($scenarios.Count) scenarios)"
}
