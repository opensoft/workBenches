#!/usr/bin/env pwsh
# Git extension: create-new-feature.ps1
# Adapted from core scripts/powershell/create-new-feature.ps1 for extension layout.
# Sources common.ps1 from the project's installed scripts, falling back to
# git-common.ps1 for minimal git helpers.
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$AllowExistingBranch,
    [switch]$DryRun,
    [string]$ShortName,
    [Parameter()]
    [long]$Number = 0,
    [switch]$Timestamp,
    [switch]$Help,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$FeatureDescription
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: ./create-new-feature.ps1 [-Json] [-DryRun] [-AllowExistingBranch] [-ShortName <name>] [-Number N] [-Timestamp] <feature description>"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Json               Output in JSON format"
    Write-Host "  -DryRun             Compute branch name without creating the branch"
    Write-Host "  -AllowExistingBranch  Switch to branch if it already exists instead of failing"
    Write-Host "  -ShortName <name>   Provide a custom short name (2-4 words) for the branch"
    Write-Host "  -Number N           Specify branch number manually (overrides auto-detection)"
    Write-Host "  -Timestamp          Use timestamp prefix (YYYYMMDD-HHMMSS) instead of sequential numbering"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Environment variables:"
    Write-Host "  GIT_BRANCH_NAME     Use this exact branch name, bypassing all prefix/suffix generation"
    Write-Host "  SPECKIT_GIT_BRANCH_TEMPLATE  Override branch_template"
    Write-Host "  SPECKIT_GIT_BRANCH_PREFIX    Override branch_prefix"
    Write-Host ""
    Write-Host "Configuration:"
    Write-Host "  branch_template     Optional template with exactly one {number}; also supports {author}, {app}, {slug}"
    Write-Host "  branch_prefix       Optional namespace prepended to branch_template"
    Write-Host ""
    exit 0
}

if ($PSBoundParameters.ContainsKey('Number') -and $Number -lt 0) {
    Write-Error "Error: -Number must be zero or greater"
    exit 1
}

if (-not $FeatureDescription -or $FeatureDescription.Count -eq 0) {
    Write-Error "Usage: ./create-new-feature.ps1 [-Json] [-DryRun] [-AllowExistingBranch] [-ShortName <name>] [-Number N] [-Timestamp] <feature description>"
    exit 1
}

$featureDesc = ($FeatureDescription -join ' ').Trim()

if ([string]::IsNullOrWhiteSpace($featureDesc)) {
    Write-Error "Error: Feature description cannot be empty or contain only whitespace"
    exit 1
}

function Get-HighestNumberFromSpecs {
    param([string]$SpecsDir)

    [long]$highest = 0
    if (Test-Path -LiteralPath $SpecsDir) {
        Get-ChildItem -LiteralPath $SpecsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d{3,})-' -and $_.Name -notmatch '^\d{8}-\d{6}-') {
                [long]$num = 0
                if ([long]::TryParse($matches[1], [ref]$num) -and $num -gt $highest) {
                    $highest = $num
                }
            }
        }
    }
    return $highest
}

function Get-HighestNumberFromNames {
    param(
        [string[]]$Names,
        [string]$ScopePrefix = ''
    )

    [long]$highest = 0
    foreach ($name in $Names) {
        if (-not $ScopePrefix -and $name.Contains('/')) {
            continue
        }
        if ($ScopePrefix -and -not $name.StartsWith($ScopePrefix, [System.StringComparison]::Ordinal)) {
            continue
        }
        if ($ScopePrefix) {
            $name = $name.Substring($ScopePrefix.Length)
        }
        $name = ($name -split '/')[-1]
        $hasTimestampPrefix = $name -match '^\d{8}-\d{6}-'
        $hasMalformedTimestamp = ($name -match '^\d{7}-\d{6}-') -or ($name -match '^(?:\d{7}|\d{8})-\d{6}$')
        if ($name -match '^(\d{3,})-' -and -not $hasTimestampPrefix -and -not $hasMalformedTimestamp) {
            [long]$num = 0
            if ([long]::TryParse($matches[1], [ref]$num) -and $num -gt $highest) {
                $highest = $num
            }
        }
    }
    return $highest
}

function Get-HighestNumberFromBranches {
    param([string]$ScopePrefix = '')

    try {
        $branches = git branch -a 2>$null
        if ($LASTEXITCODE -eq 0 -and $branches) {
            $cleanNames = $branches | ForEach-Object {
                $_.Trim() -replace '^[+*]?\s+', '' -replace '^remotes/[^/]+/', ''
            }
            return Get-HighestNumberFromNames -Names $cleanNames -ScopePrefix $ScopePrefix
        }
    } catch {
        Write-Verbose "Could not check Git branches: $_"
    }
    return 0
}

function Get-HighestNumberFromRemoteRefs {
    param([string]$ScopePrefix = '')

    [long]$highest = 0
    try {
        $remotes = git remote 2>$null
        if ($remotes) {
            foreach ($remote in $remotes) {
                $env:GIT_TERMINAL_PROMPT = '0'
                $refs = git ls-remote --heads $remote 2>$null
                $env:GIT_TERMINAL_PROMPT = $null
                if ($LASTEXITCODE -eq 0 -and $refs) {
                    $refNames = $refs | ForEach-Object {
                        if ($_ -match 'refs/heads/(.+)$') { $matches[1] }
                    } | Where-Object { $_ }
                    $remoteHighest = Get-HighestNumberFromNames -Names $refNames -ScopePrefix $ScopePrefix
                    if ($remoteHighest -gt $highest) { $highest = $remoteHighest }
                }
            }
        }
    } catch {
        Write-Verbose "Could not query remote refs: $_"
    }
    return $highest
}

function Get-NextBranchNumber {
    param(
        [string]$SpecsDir,
        [switch]$SkipFetch,
        [string]$ScopePrefix = ''
    )

    if ($SkipFetch) {
        $highestBranch = Get-HighestNumberFromBranches -ScopePrefix $ScopePrefix
        $highestRemote = Get-HighestNumberFromRemoteRefs -ScopePrefix $ScopePrefix
        $highestBranch = [Math]::Max($highestBranch, $highestRemote)
    } else {
        try {
            git fetch --all --prune 2>$null | Out-Null
        } catch { }
        $highestBranch = Get-HighestNumberFromBranches -ScopePrefix $ScopePrefix
    }

    $highestSpec = if ($ScopePrefix) { 0 } else { Get-HighestNumberFromSpecs -SpecsDir $SpecsDir }
    $maxNum = [Math]::Max($highestBranch, $highestSpec)
    return $maxNum + 1
}

$script:ownedNumberReservationRef = ''
$script:ownedNumberReservationOid = ''

function Invoke-NumberReservationGit {
    param(
        [string[]]$Arguments,
        [AllowNull()][string]$StandardInput,
        [switch]$InvariantMessages
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    if ($PSBoundParameters.ContainsKey('StandardInput')) {
        $startInfo.RedirectStandardInput = $true
        $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    }
    if ($InvariantMessages) {
        $startInfo.Environment['LC_ALL'] = 'C'
    }
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) {
            throw 'Git reservation process did not start.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($startInfo.RedirectStandardInput) {
            $process.StandardInput.Write($StandardInput)
            $process.StandardInput.Close()
        }
        $process.WaitForExit()
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdoutTask.GetAwaiter().GetResult()
            Stderr = $stderrTask.GetAwaiter().GetResult()
        }
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Remove-OwnedNumberReservation {
    param([switch]$Emergency)

    if ([string]::IsNullOrEmpty($script:ownedNumberReservationRef)) {
        return
    }

    try {
        $result = Invoke-NumberReservationGit -Arguments @(
            'update-ref',
            '-d',
            $script:ownedNumberReservationRef,
            $script:ownedNumberReservationOid
        )
    } catch {
        if ($Emergency) {
            return
        }
        throw "Error: Failed to release owned feature number reservation '$($script:ownedNumberReservationRef)'.`n$($_.Exception.Message)"
    }
    if ($result.ExitCode -ne 0) {
        if ($Emergency) {
            return
        }
        $message = "Error: Failed to release owned feature number reservation '$($script:ownedNumberReservationRef)'."
        if (-not [string]::IsNullOrWhiteSpace($result.Stderr)) {
            $message += "`n$($result.Stderr.Trim())"
        }
        throw $message
    }

    $script:ownedNumberReservationRef = ''
    $script:ownedNumberReservationOid = ''
}

function Reserve-NextBranchNumber {
    param(
        [string]$SpecsDir,
        [string]$ScopePrefix = ''
    )

    $scopeResult = Invoke-NumberReservationGit -Arguments @('hash-object', '--stdin') -StandardInput $ScopePrefix
    if ($scopeResult.ExitCode -ne 0) {
        throw 'Error: Failed to hash the sequential branch scope.'
    }
    $scopeHash = $scopeResult.Stdout.TrimEnd("`r", "`n")

    $ownerPayload = "speckit-number-reservation-owner guid=$([guid]::NewGuid().ToString('N')) pid=$PID time=$([DateTime]::UtcNow.ToString('O', [System.Globalization.CultureInfo]::InvariantCulture))"
    try {
        $ownerResult = Invoke-NumberReservationGit -Arguments @('hash-object', '-w', '--stdin') -StandardInput $ownerPayload
    } catch {
        throw "Error: Failed to create the sequential feature number reservation owner object.`n$($_.Exception.Message)"
    }
    if ($ownerResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($ownerResult.Stdout)) {
        $message = 'Error: Failed to create the sequential feature number reservation owner object.'
        if (-not [string]::IsNullOrWhiteSpace($ownerResult.Stderr)) {
            $message += "`n$($ownerResult.Stderr.Trim())"
        }
        throw $message
    }
    $ownerOid = $ownerResult.Stdout.TrimEnd("`r", "`n")
    [long]$candidate = Get-NextBranchNumber -SpecsDir $SpecsDir -SkipFetch -ScopePrefix $ScopePrefix

    while ($true) {
        $reservationNumber = '{0:000}' -f $candidate
        $reservationRef = "refs/speckit/number-reservations/v1/$scopeHash/$reservationNumber"
        $updateResult = Invoke-NumberReservationGit -Arguments @('update-ref', $reservationRef, $ownerOid, '') -InvariantMessages
        if ($updateResult.ExitCode -eq 0) {
            $script:ownedNumberReservationRef = $reservationRef
            $script:ownedNumberReservationOid = $ownerOid
            [long]$visibleCandidate = Get-NextBranchNumber -SpecsDir $SpecsDir -SkipFetch -ScopePrefix $ScopePrefix
            if ($visibleCandidate -gt $candidate) {
                Remove-OwnedNumberReservation
                $candidate = $visibleCandidate
                continue
            }
            return $candidate
        }

        $existingRef = Invoke-NumberReservationGit -Arguments @('show-ref', '--verify', '--quiet', $reservationRef)
        if ($existingRef.ExitCode -eq 0 -or $updateResult.Stderr.Contains('reference already exists', [System.StringComparison]::Ordinal)) {
            $candidate++
            continue
        }

        $message = "Error: Failed to reserve sequential feature number $reservationNumber."
        if (-not [string]::IsNullOrWhiteSpace($updateResult.Stderr)) {
            $message += "`n$($updateResult.Stderr.Trim())"
        }
        throw $message
    }
}

function ConvertTo-CleanBranchName {
    param([string]$Name)
    return $Name.ToLower() -replace '[^a-z0-9]', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
}

# ---------------------------------------------------------------------------
# Source common.ps1 from the project's installed scripts.
# Search locations in priority order:
#  1. .specify/scripts/powershell/common.ps1 under the project root
#  2. scripts/powershell/common.ps1 under the project root (source checkout)
#  3. git-common.ps1 next to this script (minimal fallback)
# ---------------------------------------------------------------------------
function Find-ProjectRoot {
    param([string]$StartDir)
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in @('.specify', '.git')) {
            if (Test-Path -LiteralPath (Join-Path $current $marker)) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { return $null }
        $current = $parent
    }
}

$projectRoot = Find-ProjectRoot -StartDir $PSScriptRoot
$commonLoaded = $false

if ($projectRoot) {
    $candidates = @(
        (Join-Path $projectRoot ".specify/scripts/powershell/common.ps1"),
        (Join-Path $projectRoot "scripts/powershell/common.ps1")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            . $candidate
            $commonLoaded = $true
            break
        }
    }
}

if (-not $commonLoaded -and (Test-Path -LiteralPath "$PSScriptRoot/git-common.ps1")) {
    . "$PSScriptRoot/git-common.ps1"
    $commonLoaded = $true
}

if (-not $commonLoaded) {
    throw "Unable to locate common script file. Please ensure the Specify core scripts are installed."
}

# Resolve repository root
if (Get-Command Get-RepoRoot -ErrorAction SilentlyContinue) {
    $repoRoot = Get-RepoRoot
} elseif ($projectRoot) {
    $repoRoot = $projectRoot
} else {
    throw "Could not determine repository root."
}

try {
    git -C $repoRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
    $hasGit = ($LASTEXITCODE -eq 0)
} catch {
    $hasGit = $false
}

$configFile = Join-Path $repoRoot '.specify/extensions/git/git-config.yml'

function Get-GitExtensionConfigValue {
    param(
        [string]$Key,
        [string]$DefaultValue,
        [string]$EnvOverrideName
    )

    if ($EnvOverrideName) {
        $overrideValue = [Environment]::GetEnvironmentVariable($EnvOverrideName)
        if (-not [string]::IsNullOrWhiteSpace($overrideValue)) {
            return $overrideValue.Trim()
        }
    }

    if (Test-Path -LiteralPath $configFile) {
        $pattern = "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$"
        $resolvedValue = $null
        foreach ($line in Get-Content -LiteralPath $configFile) {
            if ($line -match $pattern) {
                $resolvedValue = $matches[1]
            }
        }
        if ($resolvedValue) {
            $resolvedValue = ($resolvedValue -replace '\s+#.*$', '').Trim()
            $resolvedValue = $resolvedValue.Trim("'")
            $resolvedValue = $resolvedValue.Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($resolvedValue)) {
                return $resolvedValue
            }
        }
    }

    return $DefaultValue
}

function ConvertTo-BranchToken {
    param(
        [string]$Value,
        [string]$Fallback
    )

    $cleaned = ConvertTo-CleanBranchName -Name $Value
    if ($cleaned) { return $cleaned }
    return $Fallback
}

function Get-GitAuthorToken {
    $author = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $author = (git config user.name 2>$null | Out-String).Trim()
        } catch {
            Write-Verbose "Could not read Git user.name: $_"
        }
        if (-not $author) {
            try {
                $email = (git config user.email 2>$null | Out-String).Trim()
                if ($email) { $author = ($email -split '@')[0] }
            } catch {
                Write-Verbose "Could not read Git user.email: $_"
            }
        }
    }
    if (-not $author) {
        $author = if ($env:USER) { $env:USER } elseif ($env:USERNAME) { $env:USERNAME } else { 'unknown' }
    }
    return ConvertTo-BranchToken -Value $author -Fallback 'unknown'
}

function Get-AppToken {
    return ConvertTo-BranchToken -Value (Split-Path $repoRoot -Leaf) -Fallback 'app'
}

function Resolve-BranchTemplate {
    param(
        [string]$Template,
        [string]$Prefix
    )

    $normalizedPrefix = $Prefix.TrimEnd('/')
    if (-not $normalizedPrefix) { return $Template }
    if ($Template -eq $normalizedPrefix -or $Template.StartsWith("$normalizedPrefix/", [System.StringComparison]::Ordinal)) {
        return $Template
    }
    return "$normalizedPrefix/$Template"
}

function Expand-BranchTemplate {
    param(
        [string]$Template,
        [string]$FeatureNum,
        [string]$BranchSuffix
    )

    $rendered = $Template.Replace('{author}', $authorToken)
    $rendered = $rendered.Replace('{app}', $appToken)
    $rendered = $rendered.Replace('{number}', $FeatureNum)
    $rendered = $rendered.Replace('{slug}', $BranchSuffix)
    return $rendered
}

function Assert-BranchTemplateValid {
    param([string]$Template)

    $unsupported = $Template
    foreach ($token in @('{author}', '{app}', '{number}', '{slug}')) {
        $unsupported = $unsupported.Replace($token, '')
    }
    if ($unsupported.Contains('{') -or $unsupported.Contains('}')) {
        throw "branch_template contains an unsupported token; supported tokens are {author}, {app}, {number}, and {slug}."
    }
    if (([regex]::Matches($Template, '\{number\}')).Count -ne 1) {
        throw "branch_template must include exactly one {number} token so generated branches remain valid feature branches."
    }
    $numberIndex = $Template.IndexOf('{number}', [System.StringComparison]::Ordinal)
    $slugIndex = $Template.IndexOf('{slug}', [System.StringComparison]::Ordinal)
    if ($slugIndex -ge 0 -and $slugIndex -lt $numberIndex) {
        throw "branch_template must not place {slug} before {number}; use {slug} only in the final feature segment."
    }
    $featureSegment = ($Template -split '/')[-1]
    if (-not $featureSegment.StartsWith('{number}-', [System.StringComparison]::Ordinal)) {
        throw "branch_template must put {number}- at the start of the final path segment so generated branches remain valid feature branches."
    }
}

function New-BranchName {
    param(
        [string]$FeatureNum,
        [string]$BranchSuffix
    )

    return Expand-BranchTemplate -Template $branchTemplate -FeatureNum $FeatureNum -BranchSuffix $BranchSuffix
}

function Get-BranchScopePrefix {
    param(
        [string]$Template,
        [string]$BranchSuffix
    )

    $numberIndex = $Template.IndexOf('{number}', [System.StringComparison]::Ordinal)
    $slugIndex = $Template.IndexOf('{slug}', [System.StringComparison]::Ordinal)
    $indexes = @($numberIndex, $slugIndex) | Where-Object { $_ -ge 0 } | Sort-Object
    if (-not $indexes) { return '' }
    $prefix = $Template.Substring(0, $indexes[0])
    return Expand-BranchTemplate -Template $prefix -FeatureNum '' -BranchSuffix $BranchSuffix
}

function Get-FeatureNumberFromBranchName {
    param([string]$BranchName)

    $featureSegment = ($BranchName -split '/')[-1]
    if ($featureSegment -match '^(\d{8}-\d{6})-') {
        return $matches[1]
    }
    if ($featureSegment -match '^(\d+)-') {
        return $matches[1]
    }
    return $BranchName
}

function Resolve-PathFromRepoRoot {
    param([string]$RawPath)

    if ([System.IO.Path]::IsPathRooted($RawPath)) {
        return [System.IO.Path]::GetFullPath($RawPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RawPath))
}

function Resolve-GitCommonDir {
    $commonDir = git rev-parse --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonDir)) {
        return $null
    }
    $commonDir = $commonDir.Trim()
    if ([System.IO.Path]::IsPathRooted($commonDir)) {
        return [System.IO.Path]::GetFullPath($commonDir)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $commonDir))
}

function Resolve-BaseRef {
    param([string]$BaseRef)

    try {
        git show-ref --verify --quiet "refs/heads/$BaseRef" 2>$null
        if ($LASTEXITCODE -eq 0) { return $BaseRef }
    } catch { }

    try {
        git rev-parse --verify --quiet "$BaseRef^{commit}" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $BaseRef }
    } catch { }

    try {
        git show-ref --verify --quiet "refs/remotes/origin/$BaseRef" 2>$null
        if ($LASTEXITCODE -eq 0) { return "origin/$BaseRef" }
    } catch { }

    return $null
}

function ConvertFrom-GitCQuotedPath {
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
    param([switch]$NullDelimited)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $arguments = @('worktree', 'list', '--porcelain')
    if ($NullDelimited) {
        $arguments += '-z'
    }
    foreach ($argument in $arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) {
            throw 'Git worktree process did not start.'
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [PSCustomObject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
    } catch {
        throw "Failed to run 'git worktree list --porcelain$(if ($NullDelimited) { ' -z' })': $($_.Exception.Message)"
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Invoke-GitWorktreeAdd {
    param([string[]]$Arguments)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.ArgumentList.Add('worktree')
    $startInfo.ArgumentList.Add('add')
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) {
            throw 'Git worktree-add process did not start.'
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = ($stdout + $stderr).Trim() }
    } catch {
        throw "Failed to run 'git worktree add': $($_.Exception.Message)"
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Assert-WorktreeCandidateValid {
    param(
        [string]$CandidatePath,
        [string]$BranchName,
        [string]$ExpectedHead
    )

    function Invoke-CandidateGit {
        param([string[]]$Arguments)

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
        $startInfo.WorkingDirectory = $repoRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.ArgumentList.Add('-C')
        $startInfo.ArgumentList.Add($CandidatePath)
        foreach ($argument in $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }

        $process = $null
        try {
            $process = [System.Diagnostics.Process]::Start($startInfo)
            if ($null -eq $process) {
                throw 'Git candidate process did not start.'
            }
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($stdout.EndsWith("`r`n", [System.StringComparison]::Ordinal)) {
                $stdout = $stdout.Substring(0, $stdout.Length - 2)
            } elseif ($stdout.EndsWith("`n", [System.StringComparison]::Ordinal)) {
                $stdout = $stdout.Substring(0, $stdout.Length - 1)
            }
            return [PSCustomObject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
        } catch {
            throw "Failed to corroborate worktree candidate '$CandidatePath': $($_.Exception.Message)"
        } finally {
            if ($null -ne $process) {
                $process.Dispose()
            }
        }
    }

    function Resolve-CandidateGitPath {
        param(
            [string]$Value,
            [string]$BasePath
        )

        if ([System.IO.Path]::IsPathRooted($Value)) {
            return [System.IO.Path]::GetFullPath($Value)
        }
        return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Value))
    }

    function Assert-CandidateGitResult {
        param(
            $Result,
            [string]$Operation
        )

        if ($Result.ExitCode -ne 0 -or [string]::IsNullOrEmpty($Result.Stdout)) {
            $detail = $Result.Stderr.Trim()
            if ($detail) {
                throw "Worktree candidate '$CandidatePath' failed $Operation`: $detail"
            }
            throw "Worktree candidate '$CandidatePath' failed $Operation."
        }
    }

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not [System.IO.Path]::IsPathRooted($CandidatePath)) {
        throw "Worktree candidate path is not absolute: $CandidatePath"
    }
    $candidateFullPath = [System.IO.Path]::GetFullPath($CandidatePath)
    $repoFullPath = [System.IO.Path]::GetFullPath($repoRoot)
    $rootFullPath = [System.IO.Path]::GetFullPath($worktreeRoot)
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootPrefix = $rootFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $candidateFullPath.StartsWith($rootPrefix, $comparison)) {
        throw "Worktree candidate is outside the configured worktree root: $CandidatePath"
    }
    if ($candidateFullPath.Equals($repoFullPath, $comparison)) {
        throw "Worktree candidate must not be the main checkout: $CandidatePath"
    }
    if (-not [System.IO.Directory]::Exists($candidateFullPath)) {
        throw "Worktree candidate directory does not exist: $CandidatePath"
    }

    $topLevelResult = Invoke-CandidateGit -Arguments @('rev-parse', '--show-toplevel')
    Assert-CandidateGitResult -Result $topLevelResult -Operation 'canonical top-level verification'
    $topLevel = [System.IO.Path]::GetFullPath($topLevelResult.Stdout)
    if (-not $topLevel.Equals($candidateFullPath, $comparison)) {
        throw "Worktree candidate top-level does not match its path: $CandidatePath"
    }

    $commonDirResult = Invoke-CandidateGit -Arguments @('rev-parse', '--git-common-dir')
    Assert-CandidateGitResult -Result $commonDirResult -Operation 'common-directory verification'
    $candidateCommonDir = Resolve-CandidateGitPath -Value $commonDirResult.Stdout -BasePath $candidateFullPath
    $expectedCommonDir = [System.IO.Path]::GetFullPath($commonDir)
    if (-not $candidateCommonDir.Equals($expectedCommonDir, $comparison)) {
        throw "Worktree candidate belongs to a different Git common directory: $CandidatePath"
    }

    $gitDirResult = Invoke-CandidateGit -Arguments @('rev-parse', '--git-dir')
    Assert-CandidateGitResult -Result $gitDirResult -Operation 'linked-worktree git-directory verification'
    $candidateGitDir = Resolve-CandidateGitPath -Value $gitDirResult.Stdout -BasePath $candidateFullPath
    $linkedGitRoot = Join-Path $expectedCommonDir 'worktrees'
    $linkedGitPrefix = $linkedGitRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $candidateGitDir.StartsWith($linkedGitPrefix, $comparison) -or -not [System.IO.Directory]::Exists($candidateGitDir)) {
        throw "Worktree candidate is not a registered linked worktree: $CandidatePath"
    }

    $headResult = Invoke-CandidateGit -Arguments @('rev-parse', 'HEAD')
    Assert-CandidateGitResult -Result $headResult -Operation 'HEAD verification'
    if ($headResult.Stdout -cne $ExpectedHead) {
        throw "Worktree candidate HEAD does not match the worktree record: $CandidatePath"
    }

    $branchResult = Invoke-CandidateGit -Arguments @('symbolic-ref', '--quiet', 'HEAD')
    if ($branchResult.ExitCode -ne 0) {
        throw "Worktree candidate is detached instead of being on branch '$BranchName': $CandidatePath"
    }
    if ($branchResult.Stdout -cne "refs/heads/$BranchName") {
        throw "Worktree candidate is on a different branch than '$BranchName': $CandidatePath"
    }
}

function Find-WorktreePathForBranch {
    param([string]$BranchName)

    $newRecord = {
        param([string]$Path)
        return [ordered]@{
            Path = $Path
            Heads = [System.Collections.Generic.List[string]]::new()
            Branches = [System.Collections.Generic.List[string]]::new()
            DetachedCount = 0
            IsPrunable = $false
        }
    }
    $addMetadata = {
        param($Record, [string]$Field)
        if ($Field -match '^HEAD ([0-9a-f]{40,64})$') {
            $Record.Heads.Add($matches[1])
        } elseif ($Field.StartsWith('HEAD ', [System.StringComparison]::Ordinal)) {
            throw "Malformed Git worktree HEAD field: $Field"
        } elseif ($Field.StartsWith('branch refs/heads/', [System.StringComparison]::Ordinal)) {
            $branch = $Field.Substring(18)
            if ([string]::IsNullOrEmpty($branch)) {
                throw 'Malformed Git worktree branch field.'
            }
            $Record.Branches.Add($branch)
        } elseif ($Field -eq 'detached') {
            $Record.DetachedCount++
        } elseif ($Field -eq 'bare' -or $Field.StartsWith('locked', [System.StringComparison]::Ordinal) -or $Field.StartsWith('prunable', [System.StringComparison]::Ordinal)) {
            if ($Field.StartsWith('prunable', [System.StringComparison]::Ordinal)) {
                $Record.IsPrunable = $true
            }
        } else {
            throw "Malformed Git worktree field: $Field"
        }
    }
    $completeRecord = {
        param($Record)
        if ($Record.Heads.Count -ne 1) {
            throw "Malformed Git worktree record for '$($Record.Path)': expected exactly one valid HEAD field."
        }
        if ($Record.Branches.Count -gt 1 -or $Record.DetachedCount -gt 1 -or ($Record.Branches.Count -ne 0 -and $Record.DetachedCount -ne 0)) {
            throw "Ambiguous Git worktree branch state for '$($Record.Path)'."
        }
        return [PSCustomObject]@{
            Path = $Record.Path
            Head = $Record.Heads[0]
            Branch = if ($Record.Branches.Count -eq 1) { $Record.Branches[0] } else { $null }
            IsPrunable = $Record.IsPrunable
        }
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $result = Invoke-GitWorktreePorcelain -NullDelimited
    if ($result.ExitCode -eq 0) {
        if ($result.Stdout.Length -ne 0) {
            $recordTerminator = "{0}{0}" -f [char]0
            if (-not $result.Stdout.EndsWith($recordTerminator, [System.StringComparison]::Ordinal)) {
                throw 'Partial NUL-delimited Git worktree record.'
            }
            $currentRecord = $null
            $fields = $result.Stdout.Split([char]0)
            for ($index = 0; $index -lt $fields.Length - 1; $index++) {
                $field = $fields[$index]
                if ($field.Length -eq 0) {
                    if ($null -eq $currentRecord) {
                        throw 'Malformed empty NUL-delimited Git worktree record.'
                    }
                    $records.Add((& $completeRecord $currentRecord))
                    $currentRecord = $null
                } elseif ($field.StartsWith('worktree ', [System.StringComparison]::Ordinal)) {
                    if ($null -ne $currentRecord) {
                        throw 'Partial NUL-delimited Git worktree record before the next worktree field.'
                    }
                    $path = $field.Substring(9)
                    if ([string]::IsNullOrEmpty($path)) {
                        throw 'Malformed Git worktree path field.'
                    }
                    $currentRecord = & $newRecord $path
                } else {
                    if ($null -eq $currentRecord) {
                        throw "Git worktree metadata appeared outside a record: $field"
                    }
                    & $addMetadata $currentRecord $field
                }
            }
            if ($null -ne $currentRecord) {
                throw 'Partial NUL-delimited Git worktree record.'
            }
        }
    } elseif ($result.ExitCode -eq 129) {
        $result = Invoke-GitWorktreePorcelain
        if ($result.ExitCode -ne 0) {
            throw "Git worktree line-porcelain fallback failed with exit code $($result.ExitCode): $($result.Stderr.Trim())"
        }
        if ($result.Stdout.Length -ne 0) {
            if ($result.Stdout -notmatch '(?:\r?\n){2}$') {
                throw 'Partial line-delimited Git worktree record.'
            }
            $recordMatches = [regex]::Matches($result.Stdout, '(?ms)\Gworktree (?<body>.*?)(?:\r?\n){2}(?=worktree |\z)')
            $consumed = 0
            foreach ($recordMatch in $recordMatches) {
                if ($recordMatch.Index -ne $consumed) {
                    throw 'Malformed line-delimited Git worktree output between records.'
                }
                $consumed += $recordMatch.Length
                $body = $recordMatch.Groups['body'].Value
                $headMatches = [regex]::Matches($body, '(?m)^HEAD (?<head>[0-9a-f]{40,64})\r?$')
                if ($headMatches.Count -ne 1) {
                    throw 'Malformed line-delimited Git worktree record: expected exactly one valid HEAD field.'
                }
                $headMatch = $headMatches[0]
                $pathWithSeparator = $body.Substring(0, $headMatch.Index)
                if ($pathWithSeparator.EndsWith("`r`n", [System.StringComparison]::Ordinal)) {
                    $path = $pathWithSeparator.Substring(0, $pathWithSeparator.Length - 2)
                } elseif ($pathWithSeparator.EndsWith("`n", [System.StringComparison]::Ordinal)) {
                    $path = $pathWithSeparator.Substring(0, $pathWithSeparator.Length - 1)
                } else {
                    throw 'Malformed line-delimited Git worktree path boundary.'
                }
                if ([string]::IsNullOrEmpty($path)) {
                    throw 'Malformed Git worktree path field.'
                }
                $currentRecord = & $newRecord (ConvertFrom-GitCQuotedPath -Value $path)
                $currentRecord.Heads.Add($headMatch.Groups['head'].Value)
                $metadataStart = $headMatch.Index + $headMatch.Length
                $metadata = $body.Substring($metadataStart)
                if ($metadata.StartsWith("`r`n", [System.StringComparison]::Ordinal)) {
                    $metadata = $metadata.Substring(2)
                } elseif ($metadata.StartsWith("`n", [System.StringComparison]::Ordinal)) {
                    $metadata = $metadata.Substring(1)
                } elseif ($metadata.Length -ne 0) {
                    throw 'Malformed line-delimited Git worktree metadata boundary.'
                }
                if ($metadata.Length -ne 0) {
                    foreach ($field in [regex]::Split($metadata, '\r?\n')) {
                        if ($field.Length -eq 0) {
                            throw 'Malformed empty line in Git worktree metadata.'
                        }
                        & $addMetadata $currentRecord $field
                    }
                }
                $records.Add((& $completeRecord $currentRecord))
            }
            if ($consumed -ne $result.Stdout.Length) {
                throw 'Malformed or partial line-delimited Git worktree output.'
            }
        }
    } else {
        throw "Git worktree NUL-porcelain failed with exit code $($result.ExitCode): $($result.Stderr.Trim())"
    }

    $matchingRecords = @($records | Where-Object { -not $_.IsPrunable -and $_.Branch -ceq $BranchName })
    if ($matchingRecords.Count -gt 1) {
        throw "Ambiguous Git worktree output: branch '$BranchName' has multiple live candidates."
    }
    if ($matchingRecords.Count -eq 1) {
        $candidate = $matchingRecords[0]
        Assert-WorktreeCandidateValid -CandidatePath $candidate.Path -BranchName $BranchName -ExpectedHead $candidate.Head
        return $candidate.Path
    }

    return $null
}

function Assert-StateFileSafe {
    param([string]$LiteralPath)

    try {
        $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        return
    }

    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or -not ($item -is [System.IO.FileInfo])) {
        throw "Speckit state path must be a regular file or missing: $LiteralPath"
    }
}

function Initialize-SafeStateNativeApi {
    if ('Speckit.SafeStateNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.ExceptionServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace Speckit
{
    public sealed class SafeWindowsStateTransaction : IDisposable
    {
        private const uint FileListDirectory = 0x00000001;
        private const uint FileAddFile = 0x00000002;
        private const uint FileTraverse = 0x00000020;
        private const uint FileReadAttributes = 0x00000080;
        private const uint DeleteAccess = 0x00010000;
        private const uint ReadControl = 0x00020000;
        private const uint Synchronize = 0x00100000;
        private const uint GenericWrite = 0x40000000;
        private const uint ShareAll = 0x00000007;
        private const uint OpenExisting = 3;
        private const uint FileAttributeNormal = 0x00000080;
        private const uint FileAttributeDirectory = 0x00000010;
        private const uint FileAttributeReparsePoint = 0x00000400;
        private const uint FileFlagBackupSemantics = 0x02000000;
        private const uint FileFlagOpenReparsePoint = 0x00200000;
        private const uint ObjectCaseInsensitive = 0x00000040;
        private const uint FileOpen = 1;
        private const uint FileCreate = 2;
        private const uint FileSynchronousIoNonAlert = 0x00000020;
        private const uint FileNonDirectoryFile = 0x00000040;
        private const uint FileOpenReparsePoint = 0x00200000;
        private const int StatusObjectNameNotFound = unchecked((int)0xC0000034);
        private const int StatusObjectPathNotFound = unchecked((int)0xC000003A);
        private const int StatusObjectNameCollision = unchecked((int)0xC0000035);
        private const int FileStandardInfo = 1;
        private const int FileAttributeTagInfo = 9;
        private const int FileIdInfo = 18;
        private const int FileDispositionInfoEx = 21;
        private const int FileRenameInformationEx = 65;
        private const uint FileDispositionDelete = 0x00000001;
        private const uint FileDispositionPosixSemantics = 0x00000002;
        private const uint FileRenameReplaceIfExists = 0x00000001;
        private const uint FileRenamePosixSemantics = 0x00000002;
        private const uint DriveUnknown = 0;
        private const uint DriveNoRootDirectory = 1;
        private const uint DriveRemote = 4;
        private const int ErrorInvalidFunction = 1;
        private const int ErrorNotSupported = 50;
        private const int ErrorInvalidParameter = 87;
        private const int ErrorCallNotImplemented = 120;
        private const uint OwnerSecurityInformation = 0x00000001;
        private const uint DaclSecurityInformation = 0x00000004;
        private const uint SeFileObject = 1;

        private SafeFileHandle parentHandle;
        private SafeFileHandle temporaryHandle;
        private bool published;
        private bool disposed;

        public static void AssertSupported(string parentPath)
        {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT
                || Environment.OSVersion.Version.CompareTo(new Version(6, 2)) < 0)
            {
                throw new IOException("Windows state publication requires Windows 8 or Windows Server 2012 or later for FILE_ID_INFO support.");
            }

            string fullPath = Path.GetFullPath(parentPath);
            string root = Path.GetPathRoot(fullPath);
            uint driveType = string.IsNullOrEmpty(root) ? DriveNoRootDirectory : GetDriveTypeW(root);
            if (driveType == DriveRemote)
            {
                throw new IOException("Speckit state publication requires a local Git common directory; remote directories are unsupported: " + fullPath);
            }
            if (driveType == DriveUnknown)
            {
                throw new IOException("Speckit state publication requires a local Git common directory; the drive type is unknown: " + fullPath);
            }
            if (driveType == DriveNoRootDirectory)
            {
                throw new IOException("Speckit state publication requires a local Git common directory; the directory root is unavailable: " + fullPath);
            }
        }

        public SafeWindowsStateTransaction(string parentPath)
        {
            AssertSupported(parentPath);
            parentHandle = CreateFileW(
                Path.GetFullPath(parentPath),
                FileListDirectory | FileAddFile | FileTraverse | FileReadAttributes,
                ShareAll,
                IntPtr.Zero,
                OpenExisting,
                FileFlagBackupSemantics | FileFlagOpenReparsePoint,
                IntPtr.Zero);
            if (parentHandle.IsInvalid)
            {
                ThrowLastWin32("open state directory");
            }

            try
            {
                ValidateDirectory(parentHandle);
                CapabilityPreflight(parentHandle);
            }
            catch
            {
                parentHandle.Dispose();
                throw;
            }
        }

        public string TemporaryName { get; private set; }

        public void CreateTemporary()
        {
            ThrowIfDisposed();
            if (temporaryHandle != null)
            {
                throw new InvalidOperationException("The state temporary has already been created.");
            }

            byte[] random = new byte[8];
            for (int attempt = 0; attempt < 128; attempt++)
            {
                RandomNumberGenerator.Fill(random);
                TemporaryName = ".speckit-last-worktree.json.tmp."
                    + Convert.ToHexString(random).ToLowerInvariant();
                int status = CreateRelative(parentHandle, TemporaryName, out temporaryHandle);
                if (status >= 0)
                {
                    ValidateTemporarySecurity(temporaryHandle);
                    return;
                }
                if (temporaryHandle != null)
                {
                    temporaryHandle.Dispose();
                    temporaryHandle = null;
                }
                if (status != StatusObjectNameCollision)
                {
                    ThrowNtStatus(status, "create state temporary");
                }
            }
            throw new IOException("Could not create a unique state temporary.");
        }

        public void WriteAndFlush(byte[] bytes)
        {
            ThrowIfDisposed();
            ThrowIfTemporaryMissing();
            bool addedRef = false;
            try
            {
                temporaryHandle.DangerousAddRef(ref addedRef);
                using (SafeFileHandle borrowed = new SafeFileHandle(temporaryHandle.DangerousGetHandle(), false))
                using (FileStream stream = new FileStream(borrowed, FileAccess.Write, 4096, false))
                {
                    stream.Write(bytes, 0, bytes.Length);
                    stream.Flush(true);
                }
            }
            finally
            {
                if (addedRef)
                {
                    temporaryHandle.DangerousRelease();
                }
            }
        }

        public void Publish(string stateName)
        {
            ThrowIfDisposed();
            ThrowIfTemporaryMissing();
            ValidateRegularFile(temporaryHandle, "State temporary is not a regular file.");
            ValidateTemporarySecurity(temporaryHandle);
            ValidateDestination(stateName);
            RenameTemporary(stateName);
            published = true;
        }

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }

            Exception cleanupError = null;
            try
            {
                if (!published && temporaryHandle != null && !temporaryHandle.IsInvalid)
                {
                    DeleteTemporary();
                }
            }
            catch (Exception error)
            {
                cleanupError = error;
            }
            finally
            {
                if (temporaryHandle != null)
                {
                    temporaryHandle.Dispose();
                }
                if (parentHandle != null)
                {
                    parentHandle.Dispose();
                }
                disposed = true;
            }

            if (cleanupError != null)
            {
                if (cleanupError is IOException && cleanupError.InnerException is Win32Exception)
                {
                    throw cleanupError;
                }
                throw new IOException("Could not clean unpublished state temporary by handle.", cleanupError);
            }
        }

        private void CapabilityPreflight(SafeFileHandle parentHandle)
        {
            SafeFileHandle sourceHandle = null;
            SafeFileHandle destinationHandle = null;
            string sourceName = null;
            string destinationName = null;
            bool sourceDispositionRequested = false;
            bool destinationDispositionRequested = false;
            bool replacementSucceeded = false;
            Exception primaryError = null;
            Exception cleanupError = null;

            try
            {
                sourceHandle = CreateCapabilityProbe(parentHandle, "source", 0, out sourceName);
                destinationHandle = CreateCapabilityProbe(parentHandle, "destination", ShareAll, out destinationName);
                ValidateTemporarySecurity(sourceHandle);
                ValidateTemporarySecurity(destinationHandle);
                RenameRelative(sourceHandle, parentHandle, destinationName, "replace state capability probe");
                replacementSucceeded = true;
            }
            catch (Exception error)
            {
                primaryError = error;
            }
            finally
            {
                CleanupProbeHandle(ref sourceHandle, ref sourceDispositionRequested, ref cleanupError);
                if (replacementSucceeded)
                {
                    CloseProbeHandle(ref destinationHandle, ref cleanupError);
                }
                else
                {
                    CleanupProbeHandle(ref destinationHandle, ref destinationDispositionRequested, ref cleanupError);
                }
            }

            if (primaryError == null && cleanupError == null)
            {
                try
                {
                    AssertRelativeMissing(parentHandle, sourceName);
                    AssertRelativeMissing(parentHandle, destinationName);
                }
                catch (Exception error)
                {
                    primaryError = error;
                }
            }

            if (primaryError != null)
            {
                if (cleanupError != null)
                {
                    primaryError.Data["WindowsStateCleanupError"] = cleanupError;
                }
                ExceptionDispatchInfo.Capture(primaryError).Throw();
            }
            if (cleanupError != null)
            {
                throw new IOException("Could not clean the Windows state capability probe.", cleanupError);
            }
        }

        private static SafeFileHandle CreateCapabilityProbe(
            SafeFileHandle parentHandle,
            string role,
            uint shareAccess,
            out string name)
        {
            byte[] random = new byte[8];
            name = null;
            for (int attempt = 0; attempt < 128; attempt++)
            {
                RandomNumberGenerator.Fill(random);
                name = ".speckit-state-preflight."
                    + Convert.ToHexString(random).ToLowerInvariant()
                    + "."
                    + role;
                SafeFileHandle probeHandle;
                int status = CreateRelative(parentHandle, name, out probeHandle, shareAccess);
                if (status >= 0)
                {
                    return probeHandle;
                }
                if (probeHandle != null)
                {
                    probeHandle.Dispose();
                }
                if (status != StatusObjectNameCollision)
                {
                    ThrowNtStatus(status, "create state capability " + role + " probe");
                }
            }
            throw new IOException("Could not create a unique state capability " + role + " probe.");
        }

        private static void CleanupProbeHandle(
            ref SafeFileHandle handle,
            ref bool dispositionRequested,
            ref Exception cleanupError)
        {
            if (handle == null)
            {
                return;
            }

            if (!dispositionRequested && !handle.IsInvalid && !handle.IsClosed)
            {
                try
                {
                    SetProbeDisposition(handle);
                    dispositionRequested = true;
                }
                catch (Exception error)
                {
                    cleanupError = AppendCleanupError(cleanupError, error);
                }
            }
            CloseProbeHandle(ref handle, ref cleanupError);
        }

        private static void CloseProbeHandle(
            ref SafeFileHandle handle,
            ref Exception cleanupError)
        {
            if (handle == null)
            {
                return;
            }

            try
            {
                handle.Dispose();
            }
            catch (Exception error)
            {
                cleanupError = AppendCleanupError(cleanupError, error);
            }
            handle = null;
        }

        private static Exception AppendCleanupError(Exception cleanupError, Exception error)
        {
            return cleanupError == null
                ? error
                : new AggregateException(cleanupError, error);
        }

        private void ValidateDestination(string stateName)
        {
            SafeFileHandle destinationHandle;
            int status = OpenRelative(parentHandle, stateName, out destinationHandle);
            if (status == StatusObjectNameNotFound || status == StatusObjectPathNotFound)
            {
                if (destinationHandle != null)
                {
                    destinationHandle.Dispose();
                }
                return;
            }
            if (status < 0)
            {
                if (destinationHandle != null)
                {
                    destinationHandle.Dispose();
                }
                ThrowNtStatus(status, "inspect state path");
            }

            using (destinationHandle)
            {
                ValidateRegularFile(destinationHandle, "Speckit state path must be a regular file or missing.");
            }
        }

        private void RenameTemporary(string stateName)
        {
            RenameRelative(temporaryHandle, parentHandle, stateName, "publish state file");
        }

        private static void RenameRelative(
            SafeFileHandle sourceHandle,
            SafeFileHandle parentHandle,
            string destinationName,
            string operation)
        {
            byte[] nameBytes = System.Text.Encoding.Unicode.GetBytes(destinationName);
            int rootOffset = IntPtr.Size == 8 ? 8 : 4;
            int nameLengthOffset = rootOffset + IntPtr.Size;
            int nameOffset = nameLengthOffset + sizeof(uint);
            int bufferSize = checked(nameOffset + sizeof(uint) + nameBytes.Length);
            IntPtr buffer = Marshal.AllocHGlobal(bufferSize);
            bool addedRef = false;
            try
            {
                for (int index = 0; index < bufferSize; index++)
                {
                    Marshal.WriteByte(buffer, index, 0);
                }
                Marshal.WriteInt32(buffer, unchecked((int)(FileRenameReplaceIfExists | FileRenamePosixSemantics)));
                parentHandle.DangerousAddRef(ref addedRef);
                Marshal.WriteIntPtr(buffer, rootOffset, parentHandle.DangerousGetHandle());
                Marshal.WriteInt32(buffer, nameLengthOffset, nameBytes.Length);
                Marshal.Copy(nameBytes, 0, IntPtr.Add(buffer, nameOffset), nameBytes.Length);
                IoStatusBlock ioStatus;
                int status = NtSetInformationFile(
                    sourceHandle,
                    out ioStatus,
                    buffer,
                    unchecked((uint)(bufferSize)),
                    FileRenameInformationEx);
                if (status < 0)
                {
                    ThrowNtStatusWithCapability(status, operation, "FileRenameInformationEx");
                }
            }
            finally
            {
                if (addedRef)
                {
                    parentHandle.DangerousRelease();
                }
                Marshal.FreeHGlobal(buffer);
            }
        }

        private void DeleteTemporary()
        {
            IntPtr buffer = Marshal.AllocHGlobal(sizeof(uint));
            try
            {
                Marshal.WriteInt32(buffer, unchecked((int)(FileDispositionDelete | FileDispositionPosixSemantics)));
                if (!SetFileInformationByHandle(
                    temporaryHandle,
                    FileDispositionInfoEx,
                    buffer,
                    sizeof(uint)))
                {
                    ThrowLastWin32WithCapability("clean state temporary", "FileDispositionInfoEx");
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static void SetProbeDisposition(SafeFileHandle probeHandle)
        {
            IntPtr buffer = Marshal.AllocHGlobal(sizeof(uint));
            try
            {
                Marshal.WriteInt32(buffer, unchecked((int)(FileDispositionDelete | FileDispositionPosixSemantics)));
                if (!SetFileInformationByHandle(
                    probeHandle,
                    FileDispositionInfoEx,
                    buffer,
                    sizeof(uint)))
                {
                    ThrowLastWin32WithCapability("dispose state capability probe", "FileDispositionInfoEx");
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static void AssertRelativeMissing(SafeFileHandle parentHandle, string name)
        {
            SafeFileHandle relativeHandle;
            int status = OpenRelative(parentHandle, name, out relativeHandle);
            if (relativeHandle != null)
            {
                relativeHandle.Dispose();
            }
            if (status == StatusObjectNameNotFound || status == StatusObjectPathNotFound)
            {
                return;
            }
            if (status >= 0)
            {
                throw new IOException("Windows state capability probe remained after disposition and close.");
            }
            ThrowNtStatus(status, "verify state capability probe absence");
        }

        private static int CreateRelative(
            SafeFileHandle directoryHandle,
            string name,
            out SafeFileHandle fileHandle,
            uint shareAccess = 0)
        {
            IntPtr securityDescriptor = CreateCurrentUserSecurityDescriptor();
            try
            {
                return NtCreateRelative(
                    directoryHandle,
                    name,
                    GenericWrite | DeleteAccess | ReadControl | FileReadAttributes | Synchronize,
                    shareAccess,
                    FileCreate,
                    securityDescriptor,
                    out fileHandle);
            }
            finally
            {
                Marshal.FreeHGlobal(securityDescriptor);
            }
        }

        private static IntPtr CreateCurrentUserSecurityDescriptor()
        {
            byte[] descriptorBytes;
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                SecurityIdentifier currentUser = identity.User;
                FileSecurity descriptor = new FileSecurity();
                descriptor.SetOwner(currentUser);
                descriptor.SetAccessRuleProtection(true, false);
                descriptor.AddAccessRule(new FileSystemAccessRule(
                    currentUser,
                    FileSystemRights.FullControl,
                    InheritanceFlags.None,
                    PropagationFlags.None,
                    AccessControlType.Allow));
                descriptorBytes = descriptor.GetSecurityDescriptorBinaryForm();
            }

            IntPtr securityDescriptor = Marshal.AllocHGlobal(descriptorBytes.Length);
            try
            {
                Marshal.Copy(descriptorBytes, 0, securityDescriptor, descriptorBytes.Length);
                return securityDescriptor;
            }
            catch
            {
                Marshal.FreeHGlobal(securityDescriptor);
                throw;
            }
        }

        private static int OpenRelative(
            SafeFileHandle directoryHandle,
            string name,
            out SafeFileHandle fileHandle)
        {
            return NtCreateRelative(
                directoryHandle,
                name,
                FileReadAttributes | Synchronize,
                ShareAll,
                FileOpen,
                IntPtr.Zero,
                out fileHandle);
        }

        private static int NtCreateRelative(
            SafeFileHandle directoryHandle,
            string name,
            uint desiredAccess,
            uint shareAccess,
            uint disposition,
            IntPtr securityDescriptor,
            out SafeFileHandle fileHandle)
        {
            IntPtr nameBuffer = IntPtr.Zero;
            IntPtr unicodeBuffer = IntPtr.Zero;
            bool addedRef = false;
            fileHandle = null;
            try
            {
                byte[] nameBytes = System.Text.Encoding.Unicode.GetBytes(name);
                if (nameBytes.Length > ushort.MaxValue - sizeof(char))
                {
                    throw new IOException("State leaf name is too long.");
                }
                nameBuffer = Marshal.StringToHGlobalUni(name);
                UnicodeString unicodeName = new UnicodeString
                {
                    Length = unchecked((ushort)nameBytes.Length),
                    MaximumLength = unchecked((ushort)(nameBytes.Length + sizeof(char))),
                    Buffer = nameBuffer
                };
                unicodeBuffer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
                Marshal.StructureToPtr(unicodeName, unicodeBuffer, false);

                directoryHandle.DangerousAddRef(ref addedRef);
                ObjectAttributes attributes = new ObjectAttributes
                {
                    Length = Marshal.SizeOf(typeof(ObjectAttributes)),
                    RootDirectory = directoryHandle.DangerousGetHandle(),
                    ObjectName = unicodeBuffer,
                    Attributes = ObjectCaseInsensitive,
                    SecurityDescriptor = securityDescriptor,
                    SecurityQualityOfService = IntPtr.Zero
                };
                IoStatusBlock ioStatus;
                return NtCreateFile(
                    out fileHandle,
                    desiredAccess,
                    ref attributes,
                    out ioStatus,
                    IntPtr.Zero,
                    FileAttributeNormal,
                    shareAccess,
                    disposition,
                    FileSynchronousIoNonAlert | FileNonDirectoryFile | FileOpenReparsePoint,
                    IntPtr.Zero,
                    0);
            }
            finally
            {
                if (addedRef)
                {
                    directoryHandle.DangerousRelease();
                }
                if (unicodeBuffer != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(unicodeBuffer);
                }
                if (nameBuffer != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(nameBuffer);
                }
            }
        }

        private static void ValidateDirectory(SafeFileHandle handle)
        {
            FileStandardInformation standard = ReadStandardInformation(handle);
            FileAttributeTagInformation attributes = ReadAttributeTagInformation(handle);
            if (standard.Directory == 0
                || (attributes.FileAttributes & FileAttributeDirectory) == 0
                || (attributes.FileAttributes & FileAttributeReparsePoint) != 0)
            {
                throw new IOException("Speckit state parent must be a non-reparse directory.");
            }
        }

        private static void ValidateRegularFile(SafeFileHandle handle, string message)
        {
            FileStandardInformation standard = ReadStandardInformation(handle);
            FileAttributeTagInformation attributes = ReadAttributeTagInformation(handle);
            if (standard.Directory != 0
                || (attributes.FileAttributes & FileAttributeDirectory) != 0
                || (attributes.FileAttributes & FileAttributeReparsePoint) != 0)
            {
                throw new IOException(message);
            }
        }

        private static void ValidateTemporarySecurity(SafeFileHandle handle)
        {
            bool addedRef = false;
            IntPtr securityDescriptor = IntPtr.Zero;
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                SecurityIdentifier currentUser = identity.User;
                try
                {
                    handle.DangerousAddRef(ref addedRef);
                    IntPtr owner;
                    IntPtr group;
                    IntPtr dacl;
                    IntPtr sacl;
                    uint error = GetSecurityInfo(
                        handle.DangerousGetHandle(),
                        SeFileObject,
                        OwnerSecurityInformation | DaclSecurityInformation,
                        out owner,
                        out group,
                        out dacl,
                        out sacl,
                        out securityDescriptor);
                    if (error != 0)
                    {
                        throw new Win32Exception(unchecked((int)error), "inspect state temporary security");
                    }

                    int descriptorLength = checked((int)GetSecurityDescriptorLength(securityDescriptor));
                    if (descriptorLength <= 0)
                    {
                        throw new IOException("State temporary security descriptor is empty.");
                    }
                    byte[] descriptorBytes = new byte[descriptorLength];
                    Marshal.Copy(securityDescriptor, descriptorBytes, 0, descriptorBytes.Length);
                    RawSecurityDescriptor descriptor = new RawSecurityDescriptor(descriptorBytes, 0);
                    if (descriptor.Owner == null || !descriptor.Owner.Equals(currentUser))
                    {
                        throw new IOException("State temporary owner is not the current user.");
                    }
                    if ((descriptor.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0)
                    {
                        throw new IOException("State temporary DACL is not protected.");
                    }

                    RawAcl accessRules = descriptor.DiscretionaryAcl;
                    if (accessRules == null || accessRules.Count != 1)
                    {
                        throw new IOException("State temporary DACL must contain exactly one access rule.");
                    }
                    CommonAce accessRule = accessRules[0] as CommonAce;
                    if (accessRule == null
                        || accessRule.AceQualifier != AceQualifier.AccessAllowed
                        || accessRule.AceFlags != AceFlags.None
                        || accessRule.SecurityIdentifier == null
                        || !accessRule.SecurityIdentifier.Equals(currentUser)
                        || accessRule.AccessMask != unchecked((int)FileSystemRights.FullControl))
                    {
                        throw new IOException("State temporary DACL must contain only a non-inherited current-user full-control rule.");
                    }
                }
                finally
                {
                    if (securityDescriptor != IntPtr.Zero)
                    {
                        LocalFree(securityDescriptor);
                    }
                    if (addedRef)
                    {
                        handle.DangerousRelease();
                    }
                }
            }
        }

        private static FileStandardInformation ReadStandardInformation(SafeFileHandle handle)
        {
            FileStandardInformation information;
            if (!GetFileStandardInformation(
                handle,
                FileStandardInfo,
                out information,
                unchecked((uint)Marshal.SizeOf(typeof(FileStandardInformation)))))
            {
                ThrowLastWin32("inspect state object type");
            }
            return information;
        }

        private static FileAttributeTagInformation ReadAttributeTagInformation(SafeFileHandle handle)
        {
            FileAttributeTagInformation information;
            if (!GetFileAttributeTagInformation(
                handle,
                FileAttributeTagInfo,
                out information,
                unchecked((uint)Marshal.SizeOf(typeof(FileAttributeTagInformation)))))
            {
                ThrowLastWin32("inspect state object attributes");
            }
            return information;
        }

        private static FileIdentity ReadIdentity(SafeFileHandle handle)
        {
            FileIdInformation information;
            if (!GetFileIdInformation(
                handle,
                FileIdInfo,
                out information,
                unchecked((uint)Marshal.SizeOf(typeof(FileIdInformation)))))
            {
                ThrowLastWin32("authenticate state temporary");
            }
            return new FileIdentity(
                information.VolumeSerialNumber,
                information.IdentifierLow,
                information.IdentifierHigh);
        }

        private void ThrowIfDisposed()
        {
            if (disposed)
            {
                throw new ObjectDisposedException(nameof(SafeWindowsStateTransaction));
            }
        }

        private void ThrowIfTemporaryMissing()
        {
            if (temporaryHandle == null || temporaryHandle.IsInvalid || temporaryHandle.IsClosed)
            {
                throw new InvalidOperationException("The state temporary has not been created.");
            }
        }

        private static void ThrowLastWin32(string operation)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), operation);
        }

        private static void ThrowLastWin32WithCapability(string operation, string capability)
        {
            ThrowWin32WithCapability(Marshal.GetLastWin32Error(), operation, capability);
        }

        private static void ThrowNtStatusWithCapability(int status, string operation, string capability)
        {
            int errorCode = unchecked((int)RtlNtStatusToDosError(unchecked((uint)status)));
            ThrowWin32WithCapability(errorCode, operation, capability);
        }

        private static void ThrowWin32WithCapability(int errorCode, string operation, string capability)
        {
            Win32Exception error = new Win32Exception(errorCode, operation);
            if (errorCode == ErrorInvalidFunction
                || errorCode == ErrorNotSupported
                || errorCode == ErrorCallNotImplemented
                || errorCode == ErrorInvalidParameter)
            {
                throw new IOException("Windows state publication requires " + capability + " support, but this Windows/filesystem combination reports it as unsupported.", error);
            }
            throw error;
        }

        private static void ThrowNtStatus(int status, string operation)
        {
            throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(unchecked((uint)status))), operation);
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern uint GetDriveTypeW(string root);

        [DllImport("advapi32.dll")]
        private static extern uint GetSecurityInfo(
            IntPtr handle,
            uint objectType,
            uint securityInformation,
            out IntPtr owner,
            out IntPtr group,
            out IntPtr dacl,
            out IntPtr sacl,
            out IntPtr securityDescriptor);

        [DllImport("advapi32.dll")]
        private static extern uint GetSecurityDescriptorLength(IntPtr securityDescriptor);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);

        [DllImport("ntdll.dll")]
        private static extern int NtCreateFile(
            out SafeFileHandle fileHandle,
            uint desiredAccess,
            ref ObjectAttributes objectAttributes,
            out IoStatusBlock ioStatusBlock,
            IntPtr allocationSize,
            uint fileAttributes,
            uint shareAccess,
            uint createDisposition,
            uint createOptions,
            IntPtr eaBuffer,
            uint eaLength);

        [DllImport("ntdll.dll")]
        private static extern int NtSetInformationFile(
            SafeFileHandle fileHandle,
            out IoStatusBlock ioStatusBlock,
            IntPtr fileInformation,
            uint length,
            int fileInformationClass);

        [DllImport("ntdll.dll")]
        private static extern uint RtlNtStatusToDosError(uint status);

        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileStandardInformation(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            out FileStandardInformation fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileAttributeTagInformation(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            out FileAttributeTagInformation fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileIdInformation(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            out FileIdInformation fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            IntPtr fileInformation,
            uint bufferSize);

        [StructLayout(LayoutKind.Sequential)]
        private struct UnicodeString
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ObjectAttributes
        {
            public int Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoStatusBlock
        {
            public IntPtr Status;
            public UIntPtr Information;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileStandardInformation
        {
            public long AllocationSize;
            public long EndOfFile;
            public uint NumberOfLinks;
            public byte DeletePending;
            public byte Directory;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileAttributeTagInformation
        {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileIdInformation
        {
            public ulong VolumeSerialNumber;
            public ulong IdentifierLow;
            public ulong IdentifierHigh;
        }

        private readonly struct FileIdentity : IEquatable<FileIdentity>
        {
            public FileIdentity(ulong volumeSerialNumber, ulong identifierLow, ulong identifierHigh)
            {
                VolumeSerialNumber = volumeSerialNumber;
                IdentifierLow = identifierLow;
                IdentifierHigh = identifierHigh;
            }

            public ulong VolumeSerialNumber { get; }
            public ulong IdentifierLow { get; }
            public ulong IdentifierHigh { get; }

            public bool Equals(FileIdentity other)
            {
                return VolumeSerialNumber == other.VolumeSerialNumber
                    && IdentifierLow == other.IdentifierLow
                    && IdentifierHigh == other.IdentifierHigh;
            }
        }
    }

    public static class SafeStateNative
    {
        private const int ReadOnly = 0;
        private const int WriteOnly = 1;
        private const uint FileTypeMask = 0xF000;
        private const uint RegularFile = 0x8000;
        private const int AtEmptyPath = 0x1000;
        private const int AtSymlinkNoFollow = 0x100;
        private const uint StatxBasicStats = 0x7ff;

        [DllImport("libc", SetLastError = true)]
        private static extern int open(string path, int flags);

        [DllImport("libc", SetLastError = true)]
        private static extern int openat(int directoryFd, string path, int flags, uint mode);

        [DllImport("libc", SetLastError = true)]
        private static extern int close(int fd);

        [DllImport("libc", SetLastError = true)]
        private static extern int fchmod(int fd, uint mode);

        [DllImport("libc", SetLastError = true)]
        private static extern int fsync(int fd);

        [DllImport("libc", SetLastError = true)]
        private static extern int fstat(int fd, IntPtr statBuffer);

        [DllImport("libc", SetLastError = true)]
        private static extern int fstatat(int directoryFd, string path, IntPtr statBuffer, int flags);

        [DllImport("libc", SetLastError = true)]
        private static extern int statx(int directoryFd, string path, int flags, uint mask, out Statx statBuffer);

        [DllImport("libc", SetLastError = true)]
        private static extern int renameat(int oldDirectoryFd, string oldPath, int newDirectoryFd, string newPath);

        [DllImport("libc", SetLastError = true)]
        private static extern int unlinkat(int directoryFd, string path, int flags);

        public static int OpenDirectory(string path)
        {
            string fullPath = Path.GetFullPath(path);
            int flags = ReadOnly | DirectoryFlag | NoFollowFlag | CloseOnExecFlag;
            int currentFd = open(Path.DirectorySeparatorChar.ToString(), flags);
            ThrowIfFailed(currentFd, "open filesystem root");
            try
            {
                foreach (string component in fullPath.Split(
                    new[] { Path.DirectorySeparatorChar },
                    StringSplitOptions.RemoveEmptyEntries))
                {
                    int nextFd = openat(currentFd, component, flags, 0);
                    ThrowIfFailed(nextFd, "open state directory component");
                    close(currentFd);
                    currentFd = nextFd;
                }
                int result = currentFd;
                currentFd = -1;
                return result;
            }
            finally
            {
                if (currentFd >= 0)
                {
                    close(currentFd);
                }
            }
        }

        public static int CreateTemporary(int directoryFd, out string temporaryName)
        {
            int flags = WriteOnly | CreateFlag | ExclusiveFlag | NoFollowFlag | CloseOnExecFlag;
            byte[] random = new byte[8];
            for (int attempt = 0; attempt < 128; attempt++)
            {
                RandomNumberGenerator.Fill(random);
                temporaryName = ".speckit-last-worktree.json.tmp." + Convert.ToHexString(random).ToLowerInvariant();
                int fd = openat(directoryFd, temporaryName, flags, 0x180);
                if (fd >= 0)
                {
                    return fd;
                }
                int error = Marshal.GetLastWin32Error();
                if (error != 17)
                {
                    throw new Win32Exception(error, "create state temporary");
                }
            }
            throw new IOException("Could not create a unique state temporary.");
        }

        public static void FlushTemporary(int temporaryFd)
        {
            ThrowIfFailed(fchmod(temporaryFd, 0x180), "set state temporary mode");
            ThrowIfFailed(fsync(temporaryFd), "flush state temporary");
        }

        public static void AuthenticateTemporary(int temporaryFd, int directoryFd, string temporaryName)
        {
            FileIdentity descriptorIdentity = ReadIdentity(temporaryFd);
            FileIdentity leafIdentity;
            if (!TryReadIdentityAt(directoryFd, temporaryName, out leafIdentity)
                || !leafIdentity.IsRegular
                || descriptorIdentity.Device != leafIdentity.Device
                || descriptorIdentity.Inode != leafIdentity.Inode)
            {
                throw new IOException("State temporary was replaced before publication.");
            }
        }

        public static void AssertStateLeafSafe(int directoryFd, string stateName)
        {
            FileIdentity identity;
            if (TryReadIdentityAt(directoryFd, stateName, out identity) && !identity.IsRegular)
            {
                throw new IOException("Speckit state path must be a regular file or missing.");
            }
        }

        public static void Replace(int directoryFd, string temporaryName, string stateName)
        {
            ThrowIfFailed(renameat(directoryFd, temporaryName, directoryFd, stateName), "publish state file");
        }

        public static void RemoveIfAuthenticated(int temporaryFd, int directoryFd, string temporaryName)
        {
            try
            {
                FileIdentity descriptorIdentity = ReadIdentity(temporaryFd);
                FileIdentity leafIdentity;
                if (TryReadIdentityAt(directoryFd, temporaryName, out leafIdentity)
                    && descriptorIdentity.Device == leafIdentity.Device
                    && descriptorIdentity.Inode == leafIdentity.Inode)
                {
                    unlinkat(directoryFd, temporaryName, 0);
                }
            }
            catch
            {
            }
        }

        public static void Close(int fd)
        {
            if (fd >= 0)
            {
                close(fd);
            }
        }

        private static FileIdentity ReadIdentity(int fd)
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                Statx statBuffer;
                ThrowIfFailed(statx(fd, string.Empty, AtEmptyPath, StatxBasicStats, out statBuffer), "inspect state temporary descriptor");
                return new FileIdentity(statBuffer.Device, statBuffer.Inode, statBuffer.Mode);
            }

            IntPtr buffer = Marshal.AllocHGlobal(512);
            try
            {
                ThrowIfFailed(fstat(fd, buffer), "inspect state temporary descriptor");
                return ParseIdentity(buffer);
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static bool TryReadIdentityAt(int directoryFd, string name, out FileIdentity identity)
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                Statx statBuffer;
                if (statx(directoryFd, name, AtSymlinkNoFollow, StatxBasicStats, out statBuffer) == 0)
                {
                    identity = new FileIdentity(statBuffer.Device, statBuffer.Inode, statBuffer.Mode);
                    return true;
                }
                int statxError = Marshal.GetLastWin32Error();
                if (statxError == 2)
                {
                    identity = default(FileIdentity);
                    return false;
                }
                throw new Win32Exception(statxError, "inspect state path");
            }

            IntPtr buffer = Marshal.AllocHGlobal(512);
            try
            {
                if (fstatat(directoryFd, name, buffer, NoFollowAtFlag) == 0)
                {
                    identity = ParseIdentity(buffer);
                    return true;
                }
                int error = Marshal.GetLastWin32Error();
                if (error == 2)
                {
                    identity = default(FileIdentity);
                    return false;
                }
                throw new Win32Exception(error, "inspect state path");
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static FileIdentity ParseIdentity(IntPtr buffer)
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                return new FileIdentity(
                    unchecked((ulong)Marshal.ReadInt32(buffer, 0)),
                    unchecked((ulong)Marshal.ReadInt64(buffer, 8)),
                    unchecked((uint)(ushort)Marshal.ReadInt16(buffer, 4)));
            }
            return new FileIdentity(
                unchecked((ulong)Marshal.ReadInt64(buffer, 0)),
                unchecked((ulong)Marshal.ReadInt64(buffer, 8)),
                unchecked((uint)Marshal.ReadInt32(buffer, 24)));
        }

        private static void ThrowIfFailed(int result, string operation)
        {
            if (result < 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), operation);
            }
        }

        private static int DirectoryFlag => RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? 0x100000 : 0x10000;
        private static int CreateFlag => RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? 0x200 : 0x40;
        private static int ExclusiveFlag => RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? 0x800 : 0x80;
        private static int NoFollowFlag => RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? 0x100 : 0x20000;
        private static int CloseOnExecFlag => RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? 0x1000000 : 0x80000;
        private static int NoFollowAtFlag => RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? 0x20 : 0x100;

        private readonly struct FileIdentity
        {
            public FileIdentity(ulong device, ulong inode, uint mode)
            {
                Device = device;
                Inode = inode;
                Mode = mode;
            }

            public ulong Device { get; }
            public ulong Inode { get; }
            public uint Mode { get; }
            public bool IsRegular => (Mode & FileTypeMask) == RegularFile;
        }

        [StructLayout(LayoutKind.Explicit, Size = 256)]
        private struct Statx
        {
            [FieldOffset(28)] public ushort Mode;
            [FieldOffset(32)] public ulong Inode;
            [FieldOffset(136)] public uint DeviceMajor;
            [FieldOffset(140)] public uint DeviceMinor;
            public ulong Device => ((ulong)DeviceMajor << 32) | DeviceMinor;
        }
    }
}
'@
}

function Write-LastWorktreeState {
    param(
        [string]$BranchName,
        [string]$WorktreePath,
        [string]$BaseBranch,
        [scriptblock]$BeforePublish,
        [Speckit.SafeWindowsStateTransaction]$WindowsTransaction
    )

    if ([string]::IsNullOrEmpty($stateFile)) {
        return
    }

    $payload = [ordered]@{
        BRANCH_NAME = $BranchName
        WORKTREE_PATH = $WorktreePath
        BASE_BRANCH = $BaseBranch
        REPO_ROOT = $repoRoot
        UPDATED_AT = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $json = ([PSCustomObject]$payload | ConvertTo-Json -Compress) + "`n"
    $stateParent = [System.IO.Path]::GetDirectoryName($stateFile)
    if (-not $IsWindows) {
        Initialize-SafeStateNativeApi
        $directoryFd = -1
        $temporaryFd = -1
        $temporaryName = $null
        try {
            $directoryFd = [Speckit.SafeStateNative]::OpenDirectory($stateParent)
            $temporaryFd = [Speckit.SafeStateNative]::CreateTemporary($directoryFd, [ref]$temporaryName)
            $temporaryHandle = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new([IntPtr]$temporaryFd, $false)
            $stream = [System.IO.FileStream]::new($temporaryHandle, [System.IO.FileAccess]::Write)
            try {
                $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } finally {
                $stream.Dispose()
            }
            [Speckit.SafeStateNative]::FlushTemporary($temporaryFd)

            $tempFile = Join-Path $stateParent $temporaryName
            if ($null -ne $BeforePublish) {
                & $BeforePublish $tempFile $stateFile
            }

            [Speckit.SafeStateNative]::AuthenticateTemporary($temporaryFd, $directoryFd, $temporaryName)
            [Speckit.SafeStateNative]::AssertStateLeafSafe($directoryFd, [System.IO.Path]::GetFileName($stateFile))
            [Speckit.SafeStateNative]::Replace($directoryFd, $temporaryName, [System.IO.Path]::GetFileName($stateFile))
            $temporaryName = $null
        } finally {
            if ($temporaryFd -ge 0 -and $null -ne $temporaryName) {
                [Speckit.SafeStateNative]::RemoveIfAuthenticated($temporaryFd, $directoryFd, $temporaryName)
            }
            [Speckit.SafeStateNative]::Close($temporaryFd)
            [Speckit.SafeStateNative]::Close($directoryFd)
        }
        return
    }

    if ($null -eq $WindowsTransaction) {
        throw 'Windows state publication requires the pre-mutation authenticated parent transaction.'
    }

    $WindowsTransaction.CreateTemporary()
    $tempFile = Join-Path $stateParent $WindowsTransaction.TemporaryName
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $WindowsTransaction.WriteAndFlush($bytes)

    if ($null -ne $BeforePublish) {
        & $BeforePublish $tempFile $stateFile
    }

    $WindowsTransaction.Publish([System.IO.Path]::GetFileName($stateFile))
}

Set-Location $repoRoot

$specsDir = Join-Path $repoRoot 'specs'
$defaultWorktreeRoot = "../$((Split-Path $repoRoot -Leaf))-worktrees"
$checkoutMode = (Get-GitExtensionConfigValue -Key 'checkout_mode' -DefaultValue 'branch' -EnvOverrideName 'SPECKIT_GIT_CHECKOUT_MODE').ToLowerInvariant()
$branchNumbering = (Get-GitExtensionConfigValue -Key 'branch_numbering' -DefaultValue 'sequential' -EnvOverrideName 'SPECKIT_GIT_BRANCH_NUMBERING').ToLowerInvariant()
$baseBranch = Get-GitExtensionConfigValue -Key 'base_branch' -DefaultValue 'main' -EnvOverrideName 'SPECKIT_GIT_BASE_BRANCH'
$worktreeRootRaw = Get-GitExtensionConfigValue -Key 'worktree_root' -DefaultValue $defaultWorktreeRoot -EnvOverrideName 'SPECKIT_GIT_WORKTREE_ROOT'
$worktreeRoot = Resolve-PathFromRepoRoot -RawPath $worktreeRootRaw
if ($checkoutMode -notin @('branch', 'worktree')) {
    throw "checkout_mode must be 'branch' or 'worktree' (got '$checkoutMode')"
}

if ($branchNumbering -notin @('sequential', 'timestamp')) {
    throw "branch_numbering must be 'sequential' or 'timestamp' (got '$branchNumbering')"
}

if ($branchNumbering -eq 'timestamp') {
    $Timestamp = $true
}

function Get-BranchName {
    param([string]$Description)

    $stopWords = @(
        'i', 'a', 'an', 'the', 'to', 'for', 'of', 'in', 'on', 'at', 'by', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'should', 'could', 'can', 'may', 'might', 'must', 'shall',
        'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their',
        'want', 'need', 'add', 'get', 'set'
    )

    $cleanName = $Description.ToLower() -replace '[^a-z0-9\s]', ' '
    $words = $cleanName -split '\s+' | Where-Object { $_ }

    $meaningfulWords = @()
    foreach ($word in $words) {
        if ($stopWords -contains $word) { continue }
        if ($word.Length -ge 3) {
            $meaningfulWords += $word
        } elseif ($Description -cmatch "\b$($word.ToUpper())\b") {
            $meaningfulWords += $word
        }
    }

    if ($meaningfulWords.Count -gt 0) {
        $maxWords = if ($meaningfulWords.Count -eq 4) { 4 } else { 3 }
        $result = ($meaningfulWords | Select-Object -First $maxWords) -join '-'
        return $result
    } else {
        $result = ConvertTo-CleanBranchName -Name $Description
        $fallbackWords = ($result -split '-') | Where-Object { $_ } | Select-Object -First 3
        return [string]::Join('-', $fallbackWords)
    }
}

$windowsStateTransaction = $null
$windowsStatePrimaryError = $null
try {
# Check for GIT_BRANCH_NAME env var override (exact branch name, no prefix/suffix)
if ($env:GIT_BRANCH_NAME) {
    $branchName = $env:GIT_BRANCH_NAME
    # Check 244-byte limit (UTF-8) for override names
    $branchNameUtf8ByteCount = [System.Text.Encoding]::UTF8.GetByteCount($branchName)
    if ($branchNameUtf8ByteCount -gt 244) {
        throw "GIT_BRANCH_NAME must be 244 bytes or fewer in UTF-8. Provided value is $branchNameUtf8ByteCount bytes; please supply a shorter override branch name."
    }
    $featureNum = Get-FeatureNumberFromBranchName -BranchName $branchName
} else {
    $branchTemplateRaw = Get-GitExtensionConfigValue -Key 'branch_template' -DefaultValue '{number}-{slug}' -EnvOverrideName 'SPECKIT_GIT_BRANCH_TEMPLATE'
    $branchPrefix = Get-GitExtensionConfigValue -Key 'branch_prefix' -DefaultValue '' -EnvOverrideName 'SPECKIT_GIT_BRANCH_PREFIX'
    $authorToken = Get-GitAuthorToken
    $appToken = Get-AppToken
    $branchTemplate = Resolve-BranchTemplate -Template $branchTemplateRaw -Prefix $branchPrefix
    Assert-BranchTemplateValid -Template $branchTemplate

    if ($ShortName) {
        $branchSuffix = ConvertTo-CleanBranchName -Name $ShortName
    } else {
        $branchSuffix = Get-BranchName -Description $featureDesc
    }

    if ([string]::IsNullOrWhiteSpace($branchSuffix)) {
        Write-Error "Error: Feature branch name must include at least one alphanumeric slug word. Provide -ShortName with letters or digits."
        exit 1
    }

    if ($Timestamp -and $PSBoundParameters.ContainsKey('Number')) {
        Write-Warning "[specify] Warning: -Number is ignored when -Timestamp is used"
        $Number = 0
    }

    if ($Timestamp) {
        $featureNum = Get-Date -Format 'yyyyMMdd-HHmmss'
        $branchName = New-BranchName -FeatureNum $featureNum -BranchSuffix $branchSuffix
    } else {
        $branchScopePrefix = Get-BranchScopePrefix -Template $branchTemplate -BranchSuffix $branchSuffix
        if (-not $PSBoundParameters.ContainsKey('Number')) {
            if ($DryRun -and $hasGit) {
                $Number = Get-NextBranchNumber -SpecsDir $specsDir -SkipFetch -ScopePrefix $branchScopePrefix
            } elseif ($DryRun) {
                $Number = if ($branchScopePrefix) { 1 } else { (Get-HighestNumberFromSpecs -SpecsDir $specsDir) + 1 }
            } elseif ($hasGit) {
                $Number = Reserve-NextBranchNumber -SpecsDir $specsDir -ScopePrefix $branchScopePrefix
            } else {
                $Number = if ($branchScopePrefix) { 1 } else { (Get-HighestNumberFromSpecs -SpecsDir $specsDir) + 1 }
            }
        }

        $featureNum = ('{0:000}' -f $Number)
        $branchName = New-BranchName -FeatureNum $featureNum -BranchSuffix $branchSuffix
    }
}

function Get-Utf8ByteCount {
    param([string]$Value)
    return [System.Text.Encoding]::UTF8.GetByteCount($Value)
}

function Remove-LastTextElement {
    param([string]$Value)

    $textElementStarts = [System.Globalization.StringInfo]::ParseCombiningCharacters($Value)
    if ($textElementStarts.Length -le 1) {
        return ''
    }
    return $Value.Substring(0, $textElementStarts[$textElementStarts.Length - 1])
}

$maxBranchLength = 244
$branchNameUtf8ByteCount = Get-Utf8ByteCount $branchName
if ($branchNameUtf8ByteCount -gt $maxBranchLength) {
    $originalBranchName = $branchName
    $truncatedSuffix = $branchSuffix
    while ((Get-Utf8ByteCount -Value $branchName) -gt $maxBranchLength -and $truncatedSuffix.Length -gt 0) {
        $truncatedSuffix = (Remove-LastTextElement -Value $truncatedSuffix) -replace '-$', ''
        $branchName = New-BranchName -FeatureNum $featureNum -BranchSuffix $truncatedSuffix
    }
    $featureSegment = ($branchName -split '/')[-1]
    if ([string]::IsNullOrWhiteSpace($truncatedSuffix)) {
        throw "Branch name truncation removed the feature slug; shorten branch_prefix or branch_template."
    }
    if ($featureSegment -eq "$featureNum-") {
        throw "Branch name truncation left the generated branch ending at the number separator; shorten branch_prefix or branch_template."
    }
    if ((Get-Utf8ByteCount -Value $branchName) -gt $maxBranchLength) {
        throw "Branch template prefix exceeds GitHub's 244-byte branch name limit."
    }

    Write-Warning "[specify] Branch name exceeded GitHub's 244-byte limit"
    Write-Warning "[specify] Original: $originalBranchName ($branchNameUtf8ByteCount bytes)"
    Write-Warning "[specify] Truncated to: $branchName ($(Get-Utf8ByteCount $branchName) bytes)"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    git check-ref-format --branch $branchName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Invalid Git branch name: $branchName"
    }
}

$worktreePath = $null
if ($checkoutMode -eq 'worktree') {
    $worktreePath = Join-Path $worktreeRoot $branchName
}

$stateFile = $null
if (-not $DryRun -and $hasGit -and $checkoutMode -eq 'worktree') {
    $commonDir = Resolve-GitCommonDir
    if (-not $commonDir) {
        throw 'Failed to resolve the Git common directory.'
    }
    $stateFile = Join-Path $commonDir 'speckit-last-worktree.json'
    if ($IsWindows) {
        Initialize-SafeStateNativeApi
        [Speckit.SafeWindowsStateTransaction]::AssertSupported([System.IO.Path]::GetDirectoryName($stateFile))
        $windowsStateTransaction = [Speckit.SafeWindowsStateTransaction]::new([System.IO.Path]::GetDirectoryName($stateFile))
    }
    Assert-StateFileSafe -LiteralPath $stateFile
}

if (-not $DryRun) {
    if ($hasGit) {
        if ($checkoutMode -eq 'worktree') {
            $existingWorktree = Find-WorktreePathForBranch -BranchName $branchName
            if ($existingWorktree) {
                if ($AllowExistingBranch) {
                    $worktreePath = $existingWorktree
                } elseif ($Timestamp) {
                    Write-Error "Error: Branch '$branchName' already exists in worktree '$existingWorktree'. Rerun to get a new timestamp or use a different -ShortName."
                    exit 1
                } else {
                    Write-Error "Error: Branch '$branchName' is already checked out in worktree '$existingWorktree'."
                    exit 1
                }
            } else {
                $existingBranch = git branch --list $branchName 2>$null
                if ($existingBranch) {
                    if ($AllowExistingBranch) {
                        if (Test-Path -LiteralPath $worktreePath) {
                            Write-Error "Error: Worktree path '$worktreePath' already exists. Please remove it or configure a different worktree_root."
                            exit 1
                        }
                        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($worktreePath)) | Out-Null
                        $worktreeCreateResult = Invoke-GitWorktreeAdd -Arguments @($worktreePath, $branchName)
                        if ($worktreeCreateResult.ExitCode -ne 0) {
                            Write-Error "Error: Failed to add worktree '$worktreePath' for existing branch '$branchName'.`n$($worktreeCreateResult.Output)"
                            exit 1
                        }
                        Remove-OwnedNumberReservation
                    } elseif ($Timestamp) {
                        Write-Error "Error: Branch '$branchName' already exists. Rerun to get a new timestamp or use a different -ShortName."
                        exit 1
                    } else {
                        Write-Error "Error: Branch '$branchName' already exists. Please use a different feature name or specify a different number with -Number."
                        exit 1
                    }
                } else {
                    $resolvedBaseRef = Resolve-BaseRef -BaseRef $baseBranch
                    if (-not $resolvedBaseRef) {
                        Write-Error "Error: Base branch '$baseBranch' does not exist locally or on origin."
                        exit 1
                    }
                    if (Test-Path -LiteralPath $worktreePath) {
                        Write-Error "Error: Worktree path '$worktreePath' already exists. Please remove it or configure a different worktree_root."
                        exit 1
                    }
                    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($worktreePath)) | Out-Null
                    $worktreeCreateResult = Invoke-GitWorktreeAdd -Arguments @('-b', $branchName, $worktreePath, $resolvedBaseRef)
                    if ($worktreeCreateResult.ExitCode -ne 0) {
                        Write-Error "Error: Failed to create feature worktree '$worktreePath' from '$resolvedBaseRef'.`n$($worktreeCreateResult.Output)"
                        exit 1
                    }
                    Remove-OwnedNumberReservation
                }
            }
        } else {
            $branchCreated = $false
            $branchCreateError = ''
            try {
                $branchCreateError = git checkout -q -b $branchName 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0) {
                    $branchCreated = $true
                }
            } catch {
                $branchCreateError = $_.Exception.Message
            }

            if ($branchCreated) {
                Remove-OwnedNumberReservation
            }

            if (-not $branchCreated) {
                $currentBranch = ''
                try { $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch {}
                $existingBranch = git branch --list $branchName 2>$null
                if ($existingBranch) {
                    if ($AllowExistingBranch) {
                        if ($currentBranch -eq $branchName) {
                            # Already on the target branch
                        } else {
                            $switchBranchError = git checkout -q $branchName 2>&1 | Out-String
                            if ($LASTEXITCODE -ne 0) {
                                if ($switchBranchError) {
                                    Write-Error "Error: Branch '$branchName' exists but could not be checked out.`n$($switchBranchError.Trim())"
                                } else {
                                    Write-Error "Error: Branch '$branchName' exists but could not be checked out. Resolve any uncommitted changes or conflicts and try again."
                                }
                                exit 1
                            }
                        }
                    } elseif ($Timestamp) {
                        Write-Error "Error: Branch '$branchName' already exists. Rerun to get a new timestamp or use a different -ShortName."
                        exit 1
                    } else {
                        Write-Error "Error: Branch '$branchName' already exists. Please use a different feature name or specify a different number with -Number."
                        exit 1
                    }
                } else {
                    if ($branchCreateError) {
                        Write-Error "Error: Failed to create git branch '$branchName'.`n$($branchCreateError.Trim())"
                    } else {
                        Write-Error "Error: Failed to create git branch '$branchName'. Please check your git configuration and try again."
                    }
                    exit 1
                }
            }
        }
    } else {
        if ($Json) {
            [Console]::Error.WriteLine("[specify] Warning: Git repository not detected; skipped $checkoutMode creation for $branchName")
        } else {
            Write-Warning "[specify] Warning: Git repository not detected; skipped $checkoutMode creation for $branchName"
        }
    }

    $env:SPECIFY_FEATURE = $branchName
    if ($checkoutMode -eq 'worktree' -and $worktreePath) {
        $env:SPECIFY_FEATURE_WORKTREE = $worktreePath
        Initialize-SafeStateNativeApi
        Write-LastWorktreeState -BranchName $branchName -WorktreePath $worktreePath -BaseBranch $baseBranch -WindowsTransaction $windowsStateTransaction
    }
}

if ($Json) {
    $obj = [ordered]@{
        BRANCH_NAME = $branchName
        FEATURE_NUM = $featureNum
        CHECKOUT_MODE = $checkoutMode
        HAS_GIT = $hasGit
    }
    if ($checkoutMode -eq 'worktree') {
        $obj['BASE_BRANCH'] = $baseBranch
        $obj['WORKTREE_PATH'] = $worktreePath
    }
    if ($DryRun) {
        $obj['DRY_RUN'] = $true
    }
    [PSCustomObject]$obj | ConvertTo-Json -Compress
} else {
    Write-Output "BRANCH_NAME: $branchName"
    Write-Output "FEATURE_NUM: $featureNum"
    Write-Output "CHECKOUT_MODE: $checkoutMode"
    Write-Output "HAS_GIT: $hasGit"
    if ($checkoutMode -eq 'worktree') {
        Write-Output "BASE_BRANCH: $baseBranch"
        Write-Output "WORKTREE_PATH: $worktreePath"
    }
    if (-not $DryRun) {
        Write-Output "SPECIFY_FEATURE environment variable set to: $branchName"
    }
}
} catch {
    $windowsStatePrimaryError = $_
    throw
} finally {
    try {
        if ($null -ne $windowsStateTransaction) {
            try {
                $windowsStateTransaction.Dispose()
            } catch {
                if ($null -ne $windowsStatePrimaryError) {
                    Write-Error -Exception $_.Exception -Message "State publication also failed to clean its authenticated temporary: $($_.Exception.Message)" -ErrorAction Continue
                } else {
                    throw
                }
            }
        }
    } finally {
        Remove-OwnedNumberReservation -Emergency
    }
}
